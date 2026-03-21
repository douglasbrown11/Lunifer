import Foundation
import Combine
import CoreMotion
import UserNotifications

// ─────────────────────────────────────────────────────────────
// SleepFeatureCollector
// ─────────────────────────────────────────────────────────────
// Continuously collects the raw signals that the sleep prediction
// model needs. Each signal maps to one feature variable:
//
//   Feature                        Source
//   ─────────────────────────────  ──────────────────────────
//   isStationary                   CMMotionActivityManager
//   stationaryDurationMinutes      time since last non-stationary
//   timeSinceLastInteraction       app lifecycle / NotificationCenter
//   timeOfDay                      system clock (fractional hours)
//   unlockCountLast30Min           Darwin notify (screen lock)
//   isSleepFocusActive             UNNotificationSettings
//   dayOfWeek                      system clock (1=Sun … 7=Sat)
//   historicalAvgSleepOnset        rolling average from SleepTracker
//
// This class does NOT make predictions — it just keeps the data
// fresh so SleepPredictionModel can read a snapshot at any time.

@MainActor
final class SleepFeatureCollector: ObservableObject {

    // MARK: - Published feature values

    /// True when CoreMotion says the device is stationary.
    @Published private(set) var isStationary: Bool = false

    /// Minutes the device has been continuously stationary.
    @Published private(set) var stationaryDurationMinutes: Double = 0

    /// Minutes since the user last interacted with the phone
    /// (app foregrounded, screen unlocked, etc.).
    @Published private(set) var timeSinceLastInteractionMinutes: Double = 0

    /// Current time of day as fractional hours (0.0 – 24.0).
    /// Example: 11:30 PM = 23.5
    @Published private(set) var timeOfDay: Double = 0

    /// Number of screen unlock events in the last 30 minutes.
    @Published private(set) var unlockCountLast30Min: Int = 0

    /// True when the user has a Focus mode active that silences
    /// notifications (Sleep Focus, Do Not Disturb, etc.).
    @Published private(set) var isSleepFocusActive: Bool = false

    /// Day of week: 1 = Sunday, 2 = Monday … 7 = Saturday.
    @Published private(set) var dayOfWeek: Int = 1

    /// Rolling average sleep-onset time as fractional hours.
    /// Starts at nil until we have at least one night of data.
    @Published var historicalAvgSleepOnset: Double? = nil

    // MARK: - Private state

    private let motionActivityManager = CMMotionActivityManager()
    private var stationarySince: Date? = nil
    private var lastInteractionDate: Date = Date()
    private var recentUnlockTimestamps: [Date] = []
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    /// Call once when the app launches (e.g. from ContentView .task).
    /// Starts all listeners and a 60-second refresh timer.
    func startCollecting() {
        startMotionUpdates()
        observeAppLifecycle()
        loadHistoricalAverage()

        // Refresh computed features every 60 seconds
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 60,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDerivedFeatures()
            }
        }

        // Initial snapshot
        refreshDerivedFeatures()
    }

    /// Call when the app is terminating or the collector is no longer needed.
    func stopCollecting() {
        motionActivityManager.stopActivityUpdates()
        refreshTimer?.invalidate()
        refreshTimer = nil
        cancellables.removeAll()
    }

    /// Returns a snapshot of all current feature values in a struct
    /// that the prediction model can consume.
    func currentFeatures() -> SleepFeatures {
        SleepFeatures(
            isStationary: isStationary,
            stationaryDurationMinutes: stationaryDurationMinutes,
            timeSinceLastInteractionMinutes: timeSinceLastInteractionMinutes,
            timeOfDay: timeOfDay,
            unlockCountLast30Min: unlockCountLast30Min,
            isSleepFocusActive: isSleepFocusActive,
            dayOfWeek: dayOfWeek,
            historicalAvgSleepOnset: historicalAvgSleepOnset
        )
    }

    // MARK: - CoreMotion: Stationary detection

    private func startMotionUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("⚠️ SleepFeatureCollector: Motion activity not available on this device")
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
            // Just became stationary — start the clock
            stationarySince = Date()
        } else if !isStationary {
            // User moved — reset
            stationarySince = nil
            stationaryDurationMinutes = 0
        }

        // Update duration if still stationary
        if isStationary, let since = stationarySince {
            stationaryDurationMinutes = Date().timeIntervalSince(since) / 60.0
        }
    }

    // MARK: - App lifecycle: last interaction tracking

    private func observeAppLifecycle() {
        // Track when the user brings the app to the foreground
        // Each foreground event counts as a "phone interaction"
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recordInteraction()
                }
            }
            .store(in: &cancellables)

        // Track when the app goes to background (screen locked or switched away)
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    // Log as an unlock event (user was actively using phone)
                    self?.recordUnlockEvent()
                }
            }
            .store(in: &cancellables)
    }

    private func recordInteraction() {
        lastInteractionDate = Date()
        recordUnlockEvent()
        timeSinceLastInteractionMinutes = 0
    }

    private func recordUnlockEvent() {
        let now = Date()
        recentUnlockTimestamps.append(now)

        // Prune timestamps older than 30 minutes
        let cutoff = now.addingTimeInterval(-30 * 60)
        recentUnlockTimestamps.removeAll { $0 < cutoff }
        unlockCountLast30Min = recentUnlockTimestamps.count
    }

    // MARK: - Focus mode detection

    private func checkSleepFocusStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor [weak self] in
                // When a Focus mode that silences notifications is active,
                // the notification setting will show as .disabled or the
                // alertSetting will be .disabled. This isn't a perfect 1:1
                // map to "Sleep Focus" specifically, but it catches DND,
                // Sleep Focus, and custom Focus modes that silence alerts.
                let silenced = settings.alertSetting == .disabled
                self?.isSleepFocusActive = silenced
            }
        }
    }

    // MARK: - Derived / time-based features

    private func refreshDerivedFeatures() {
        let now = Date()
        let cal = Calendar.current

        // Time since last interaction
        timeSinceLastInteractionMinutes = now.timeIntervalSince(lastInteractionDate) / 60.0

        // Stationary duration (keep ticking if still stationary)
        if isStationary, let since = stationarySince {
            stationaryDurationMinutes = now.timeIntervalSince(since) / 60.0
        }

        // Time of day as fractional hours
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        timeOfDay = Double(hour) + Double(minute) / 60.0

        // Day of week
        dayOfWeek = cal.component(.weekday, from: now)

        // Prune old unlock timestamps
        let cutoff = now.addingTimeInterval(-30 * 60)
        recentUnlockTimestamps.removeAll { $0 < cutoff }
        unlockCountLast30Min = recentUnlockTimestamps.count

        // Focus mode
        checkSleepFocusStatus()
    }

    // MARK: - Historical average persistence

    private let historicalKey = "lunifer_avg_sleep_onset"

    /// Load the stored historical average from UserDefaults.
    private func loadHistoricalAverage() {
        let stored = UserDefaults.standard.double(forKey: historicalKey)
        if stored > 0 {
            historicalAvgSleepOnset = stored
        }
    }

    /// Called by SleepTracker when a new sleep-onset is detected.
    /// Updates the rolling average and persists it.
    func updateHistoricalAverage(newOnsetHour: Double) {
        if let current = historicalAvgSleepOnset {
            // Exponential moving average with alpha = 0.3
            // Recent nights matter more than old ones, but the average
            // stays stable. alpha = 0.3 means ~70% old data, ~30% new night.
            historicalAvgSleepOnset = current * 0.7 + newOnsetHour * 0.3
        } else {
            historicalAvgSleepOnset = newOnsetHour
        }
        UserDefaults.standard.set(historicalAvgSleepOnset ?? 0, forKey: historicalKey)
    }
}

// ─────────────────────────────────────────────────────────────
// SleepFeatures — A snapshot of all features at one moment
// ─────────────────────────────────────────────────────────────
// This struct is what gets passed to SleepPredictionModel.
// It's a plain value type — no side effects, easy to test.

struct SleepFeatures {
    let isStationary: Bool
    let stationaryDurationMinutes: Double
    let timeSinceLastInteractionMinutes: Double
    let timeOfDay: Double                       // 0.0 – 24.0
    let unlockCountLast30Min: Int
    let isSleepFocusActive: Bool
    let dayOfWeek: Int                          // 1 = Sun … 7 = Sat
    let historicalAvgSleepOnset: Double?         // nil if no history yet
}
