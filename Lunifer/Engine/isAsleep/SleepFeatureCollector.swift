import Foundation
import UIKit
import Combine
import CoreMotion
import UserNotifications

// ─────────────────────────────────────────────────────────────
// SleepFeatureCollector (Background-Safe)
// ─────────────────────────────────────────────────────────────.
//
// KEY DESIGN: This collector works even when the app is suspended.
// Instead of relying on real-time timers (which iOS kills in background),
// it persists interaction timestamps to UserDefaults and queries
// CoreMotion's historical activity buffer when the app wakes up.
//
// TWO MODES OF OPERATION:
//
//   1. FOREGROUND (app is open):
//      - Tracks interactions live via app lifecycle notifications
//      - CoreMotion delivers real-time stationary updates
//      - All features update on a 60-second timer
//
//   2. BACKGROUND / RETROACTIVE (app was suspended):
//      - On wake-up, queries CoreMotion for historical activity
//      - Reads persisted last-interaction timestamp from UserDefaults
//      - Reconstructs what happened while the app was asleep
//
// Feature variables:
//   isStationary                   CoreMotion (live or historical)
//   stationaryDurationMinutes      derived from motion history
//   timeSinceLastInteraction       persisted timestamps + lifecycle
//   timeOfDay                      system clock
//   unlockCountLast30Min           persisted interaction log
//   isSleepFocusActive             UNNotificationSettings
//   dayOfWeek                      system clock
//   historicalAvgSleepOnset        rolling average (UserDefaults)

@MainActor
final class SleepFeatureCollector: ObservableObject {

    // MARK: - Published feature values

    @Published private(set) var isStationary: Bool = false
    @Published private(set) var stationaryDurationMinutes: Double = 0
    @Published private(set) var timeSinceLastInteractionMinutes: Double = 0
    @Published private(set) var timeOfDay: Double = 0
    @Published private(set) var unlockCountLast30Min: Int = 0
    @Published private(set) var isSleepFocusActive: Bool = false
    @Published private(set) var dayOfWeek: Int = 1
    @Published var historicalAvgSleepOnsetWeekday: Double? = nil
    @Published var historicalAvgSleepOnsetWeekend: Double? = nil

    // MARK: - Private state

    private let motionActivityManager = CMMotionActivityManager()
    private var stationarySince: Date? = nil
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let trackingStore = SleepTrackingStore.shared

    // MARK: - Lifecycle

    /// Call once when the app launches. Starts live listeners
    /// and loads any persisted state from before the app was suspended.
    func startCollecting() {
        loadPersistedState()
        startMotionUpdates()
        observeAppLifecycle()

        // Refresh computed features every 60 seconds while foregrounded
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 60,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDerivedFeatures()
            }
        }

        refreshDerivedFeatures()
    }

    func stopCollecting() {
        motionActivityManager.stopActivityUpdates()
        refreshTimer?.invalidate()
        refreshTimer = nil
        cancellables.removeAll()
    }

    /// Returns a snapshot of all current feature values.
    func currentFeatures() -> SleepFeatures {
        let onset = isWeekend(Date())
            ? historicalAvgSleepOnsetWeekend
            : historicalAvgSleepOnsetWeekday
        return SleepFeatures(
            isStationary: isStationary,
            stationaryDurationMinutes: stationaryDurationMinutes,
            timeSinceLastInteractionMinutes: timeSinceLastInteractionMinutes,
            timeOfDay: timeOfDay,
            unlockCountLast30Min: unlockCountLast30Min,
            isSleepFocusActive: isSleepFocusActive,
            dayOfWeek: dayOfWeek,
            historicalAvgSleepOnset: onset
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Retroactive analysis (called from background task)
    // ─────────────────────────────────────────────────────────
    // This is the key method for background operation. When the app
    // wakes up (via BGProcessingTask or user opening the app), this
    // queries CoreMotion's historical buffer to figure out what
    // happened while the app was suspended.

    /// Queries CoreMotion for historical motion activity between two dates.
    /// Returns an array of (date, isStationary) pairs at ~5-minute resolution.
    nonisolated func queryMotionHistory(from start: Date, to end: Date) async -> [MotionSample] {
        guard CMMotionActivityManager.isActivityAvailable() else { return [] }

        let manager = CMMotionActivityManager()
        return await withCheckedContinuation { (continuation: CheckedContinuation<[MotionSample], Never>) in
            manager.queryActivityStarting(
                from: start,
                to: end,
                to: .main
            ) { activities, error in
                guard let activities, error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                let samples = activities.map { activity in
                    MotionSample(
                        date: activity.startDate,
                        isStationary: activity.stationary,
                        confidence: activity.confidence
                    )
                }
                continuation.resume(returning: samples)
            }
        }
    }

    /// Reconstructs features for a specific point in time using
    /// persisted data and CoreMotion history. Used for retroactive
    /// sleep analysis when the app was suspended overnight.
    func reconstructFeatures(at date: Date, motionHistory: [MotionSample]) -> SleepFeatures {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)

        // Find motion state at this time
        let relevantMotion = motionHistory
            .filter { $0.date <= date }
            .last

        let stationary = relevantMotion?.isStationary ?? true

        // Calculate how long the device had been stationary at this point
        var stationaryMinutes: Double = 0
        if stationary {
            // Walk backward through motion history to find when stationary began
            let earlier = motionHistory.filter { $0.date <= date }.reversed()
            var stationaryStart = date
            for sample in earlier {
                if sample.isStationary {
                    stationaryStart = sample.date
                } else {
                    break
                }
            }
            stationaryMinutes = date.timeIntervalSince(stationaryStart) / 60.0
        }

        // Get interaction history from persisted log
        let interactionLog = loadInteractionLog()
        let lastInteraction = interactionLog
            .filter { $0 <= date }
            .max() ?? date.addingTimeInterval(-8 * 3600) // fallback: 8 hours ago

        let timeSinceInteraction = date.timeIntervalSince(lastInteraction) / 60.0

        // Count interactions in the 30 minutes before this timestamp
        let window = date.addingTimeInterval(-30 * 60)
        let recentInteractions = interactionLog.filter { $0 >= window && $0 <= date }

        let onset = isWeekend(date)
            ? historicalAvgSleepOnsetWeekend
            : historicalAvgSleepOnsetWeekday
        return SleepFeatures(
            isStationary: stationary,
            stationaryDurationMinutes: stationaryMinutes,
            timeSinceLastInteractionMinutes: timeSinceInteraction,
            timeOfDay: Double(hour) + Double(minute) / 60.0,
            unlockCountLast30Min: recentInteractions.count,
            isSleepFocusActive: false, // can't determine retroactively
            dayOfWeek: cal.component(.weekday, from: date),
            historicalAvgSleepOnset: onset
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - CoreMotion: live stationary detection
    // ─────────────────────────────────────────────────────────

    private func startMotionUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("⚠️ SleepFeatureCollector: Motion activity not available")
            return
        }

        motionActivityManager.startActivityUpdates(to: .main) { [weak self] activity in
            Task { @MainActor [weak self] in
                guard let self, let activity else { return }
                self.handleMotionUpdate(activity)
            }
        }
    }

    private func handleMotionUpdate(_ activity: CMMotionActivity) {
        let wasStationary = isStationary
        isStationary = activity.stationary

        if isStationary && !wasStationary {
            stationarySince = Date()
        } else if !isStationary {
            stationarySince = nil
            stationaryDurationMinutes = 0
        }

        if isStationary, let since = stationarySince {
            stationaryDurationMinutes = Date().timeIntervalSince(since) / 60.0
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - App lifecycle: persisted interaction tracking
    // ─────────────────────────────────────────────────────────
    // Every interaction is saved to UserDefaults so we can
    // reconstruct the timeline even after the app was suspended.

    private func observeAppLifecycle() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recordInteraction()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recordInteraction()
                }
            }
            .store(in: &cancellables)
    }

    private func recordInteraction() {
        let now = Date()
        trackingStore.recordInteraction(at: now)
        let log = loadInteractionLog()

        // Update live features
        timeSinceLastInteractionMinutes = 0
        let window = now.addingTimeInterval(-30 * 60)
        unlockCountLast30Min = log.filter { $0 >= window }.count
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Persisted interaction log (UserDefaults)
    // ─────────────────────────────────────────────────────────

    private func loadInteractionLog() -> [Date] {
        trackingStore.loadInteractionLog()
    }

    private func saveInteractionLog(_ log: [Date]) {
        trackingStore.saveInteractionLog(log)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Focus mode detection
    // ─────────────────────────────────────────────────────────

    private func checkSleepFocusStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor [weak self] in
                let silenced = settings.alertSetting == .disabled
                self?.isSleepFocusActive = silenced
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Derived features refresh
    // ─────────────────────────────────────────────────────────

    private func refreshDerivedFeatures() {
        let now = Date()
        let cal = Calendar.current

        // Time since last interaction (read from persisted timestamp)
        if let lastInteraction = trackingStore.lastInteractionDate() {
            timeSinceLastInteractionMinutes = now.timeIntervalSince(lastInteraction) / 60.0
        }

        // Stationary duration
        if isStationary, let since = stationarySince {
            stationaryDurationMinutes = now.timeIntervalSince(since) / 60.0
        }

        // Time of day
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        timeOfDay = Double(hour) + Double(minute) / 60.0

        // Day of week
        dayOfWeek = cal.component(.weekday, from: now)

        // Unlock count from persisted log
        let log = loadInteractionLog()
        let window = now.addingTimeInterval(-30 * 60)
        unlockCountLast30Min = log.filter { $0 >= window }.count

        // Focus mode
        checkSleepFocusStatus()
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Persisted state loading
    // ─────────────────────────────────────────────────────────

    private func loadPersistedState() {
        // Load weekday / weekend averages
        historicalAvgSleepOnsetWeekday = trackingStore.historicalAverageSleepOnsetWeekday()
        historicalAvgSleepOnsetWeekend = trackingStore.historicalAverageSleepOnsetWeekend()

        // One-time migration: if no split averages exist yet but a legacy single
        // average does, seed both buckets from it so existing users keep their data.
        if historicalAvgSleepOnsetWeekday == nil,
           historicalAvgSleepOnsetWeekend == nil,
           let legacy = trackingStore.historicalAverageSleepOnset() {
            historicalAvgSleepOnsetWeekday = legacy
            historicalAvgSleepOnsetWeekend = legacy
            trackingStore.setHistoricalAverageSleepOnsetWeekday(legacy)
            trackingStore.setHistoricalAverageSleepOnsetWeekend(legacy)
        }

        // Last interaction date
        if let lastInteraction = trackingStore.lastInteractionDate() {
            timeSinceLastInteractionMinutes = Date().timeIntervalSince(lastInteraction) / 60.0
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Historical average
    // ─────────────────────────────────────────────────────────

    /// Updates the weekday or weekend rolling average depending on which day `date` falls on.
    func updateHistoricalAverage(newOnsetHour: Double, for date: Date) {
        if isWeekend(date) {
            if let current = historicalAvgSleepOnsetWeekend {
                historicalAvgSleepOnsetWeekend = current * 0.7 + newOnsetHour * 0.3
            } else {
                historicalAvgSleepOnsetWeekend = newOnsetHour
            }
            trackingStore.setHistoricalAverageSleepOnsetWeekend(historicalAvgSleepOnsetWeekend)
        } else {
            if let current = historicalAvgSleepOnsetWeekday {
                historicalAvgSleepOnsetWeekday = current * 0.7 + newOnsetHour * 0.3
            } else {
                historicalAvgSleepOnsetWeekday = newOnsetHour
            }
            trackingStore.setHistoricalAverageSleepOnsetWeekday(historicalAvgSleepOnsetWeekday)
        }
    }

    // MARK: - Weekend helper

    private func isWeekend(_ date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 || weekday == 7  // 1 = Sunday, 7 = Saturday
    }
}

// ─────────────────────────────────────────────────────────────
// MotionSample — a single point from CoreMotion history
// ─────────────────────────────────────────────────────────────

struct MotionSample {
    let date: Date
    let isStationary: Bool
    let confidence: CMMotionActivityConfidence
}

// ─────────────────────────────────────────────────────────────
// SleepFeatures — snapshot of all features at one moment
// ─────────────────────────────────────────────────────────────

struct SleepFeatures {
    let isStationary: Bool
    let stationaryDurationMinutes: Double
    let timeSinceLastInteractionMinutes: Double
    let timeOfDay: Double
    let unlockCountLast30Min: Int
    let isSleepFocusActive: Bool
    let dayOfWeek: Int
    let historicalAvgSleepOnset: Double?
}
