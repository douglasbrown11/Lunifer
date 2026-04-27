import Foundation
import Combine
import SwiftUI
import BackgroundTasks

// ─────────────────────────────────────────────────────────────
// SleepTracker (Background-Safe)
// ─────────────────────────────────────────────────────────────
// Orchestrates sleep detection across both foreground and background.
//
// ARCHITECTURE:
//
//   The old approach ran a 5-minute timer that only worked while
//   the app was in the foreground. This version uses two strategies:
//
//   1. FOREGROUND: Same 5-minute prediction loop (when user has app open)
//
//   2. BACKGROUND: Uses BGProcessingTask to wake up periodically.
//      When woken, it queries CoreMotion's historical activity buffer
//      and the persisted interaction log to retroactively reconstruct
//      what happened while the app was suspended.
//
//   3. APP RETURN: When the user opens the app in the morning,
//      runs a full retroactive analysis of the overnight period
//      to fill in any gaps the background tasks missed.
//
// BACKGROUND TASK SETUP:
//   The background task ID must be registered in Info.plist under
//   BGTaskSchedulerPermittedIdentifiers:
//     - "com.lunifer.sleepAnalysis"
//
//   And in your Xcode project:
//     Target → Signing & Capabilities → + Background Modes
//     Check: "Background processing"

@MainActor
final class SleepTracker: ObservableObject {

    static let shared = SleepTracker()

    // Background task identifier or string identifier — must match Info.plist
    nonisolated static let backgroundTaskID = "com.lunifer.sleepAnalysis"

    // MARK: - Published state

    @Published private(set) var isAsleep: Bool = false
    @Published private(set) var sleepProbability: Double = 0
    @Published private(set) var estimatedSleepOnset: Date? = nil
    @Published private(set) var estimatedWakeTime: Date? = nil
    @Published private(set) var latestPrediction: SleepPrediction? = nil
    @Published private(set) var predictionHistory: [SleepPrediction] = []

    // MARK: - Components

    let featureCollector = SleepFeatureCollector()
    private var model = SleepPredictionModel()
    private var predictionTimer: Timer?
    private let predictionInterval: TimeInterval = 5 * 60

    // State machine
    private let consecutiveThreshold = 3
    private var consecutiveAsleepCount = 0
    private var consecutiveAwakeCount = 0
    private let wakeConsecutiveThreshold = 2

    private let trackingStore = SleepTrackingStore.shared

    // ─────────────────────────────────────────────────────────
    // MARK: - Lifecycle
    // ─────────────────────────────────────────────────────────

    /// Called once at app launch. Starts foreground tracking,
    /// runs retroactive analysis for any missed overnight period,
    /// and schedules the next background task.
    func startTracking() async {
        featureCollector.startCollecting()

        // Run retroactive analysis for the overnight period we missed
        await runRetroactiveAnalysis()

        // Start the foreground prediction timer
        predictionTimer = Timer.scheduledTimer(
            withTimeInterval: predictionInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runLivePrediction()
            }
        }

        // Schedule the next background wake-up
        scheduleBackgroundTask()

        // Run an initial live prediction after a short delay
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        runLivePrediction()
    }

    func stopTracking() {
        featureCollector.stopCollecting()
        predictionTimer?.invalidate()
        predictionTimer = nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Background task registration
    // ─────────────────────────────────────────────────────────
    // Call this from LuniferApp.init() to register the handler.

    nonisolated static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskID,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            Task { @MainActor in
                await SleepTracker.shared.handleBackgroundTask(processingTask)
            }
        }
    }

    /// Schedules the next background processing task.
    /// iOS decides exactly when to run it, but we request it
    /// during the overnight window for best results.
    func scheduleBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskID)

        // Ask iOS to run this task no earlier than 30 minutes from now.
        // iOS will find an optimal time based on battery, charging, etc.
        request.earliestBeginDate = Date().addingTimeInterval(30 * 60)

        // We don't need network, just CPU for CoreMotion queries
        request.requiresNetworkConnectivity = false

        // Prefer running while charging (phone is likely on nightstand)
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Background sleep analysis task scheduled")
        } catch {
            print("⚠️ Failed to schedule background task: \(error.localizedDescription)")
        }
    }

    /// Called by iOS when the background task fires.
    private func handleBackgroundTask(_ task: BGProcessingTask) async {
        // Schedule the next one before we do work
        scheduleBackgroundTask()

        // Set up an expiration handler — iOS can cancel us at any time
        task.expirationHandler = {
            // Clean up if iOS cuts us short
            print("⚠️ Background sleep analysis expired by iOS")
        }

        // Run the retroactive analysis
        await runRetroactiveAnalysis()

        // Check battery while we're awake — warn user if phone
        // won't last until their alarm
        await BatteryAlarmNotification.shared.checkAndWarnIfNeeded()

        // Tell iOS we're done
        task.setTaskCompleted(success: true)
        print("✅ Background sleep analysis completed")
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Retroactive analysis
    // ─────────────────────────────────────────────────────────
    // This is the core of the background-safe architecture.
    // Instead of needing real-time predictions, it reconstructs
    // the overnight period using CoreMotion history + persisted
    // interaction timestamps.

    /// Analyzes the period since the last analysis (or last 12 hours)
    /// by querying CoreMotion and interaction logs retroactively.
    func runRetroactiveAnalysis() async {
        let now = Date()

        // Figure out where to start: last analysis time or 12 hours ago
        let analysisStart: Date
        if let lastAnalysisDate = trackingStore.lastRetroactiveAnalysisDate() {
            analysisStart = lastAnalysisDate
        } else {
            analysisStart = now.addingTimeInterval(-12 * 3600)
        }

        // Don't re-analyze if we ran very recently (< 10 minutes ago)
        if now.timeIntervalSince(analysisStart) < 10 * 60 { return }

        print("🔍 Running retroactive sleep analysis from \(analysisStart.formatted()) to \(now.formatted())")

        // Query CoreMotion for the entire missed period
        let motionHistory = await featureCollector.queryMotionHistory(
            from: analysisStart,
            to: now
        )

        // Step through the missed period in 5-minute increments,
        // reconstructing features and running predictions at each step
        var analysisTime = analysisStart
        let stepInterval: TimeInterval = 5 * 60
        var retroPredictions: [(date: Date, prediction: SleepPrediction)] = []

        while analysisTime <= now {
            let features = featureCollector.reconstructFeatures(
                at: analysisTime,
                motionHistory: motionHistory
            )
            let prediction = model.predict(features: features)
            retroPredictions.append((date: analysisTime, prediction: prediction))
            analysisTime = analysisTime.addingTimeInterval(stepInterval)
        }

        // Process the retroactive predictions through the state machine
        processRetroPredictions(retroPredictions)

        // Mark this analysis as complete
        trackingStore.setLastRetroactiveAnalysisDate(now)
    }

    /// Runs the sleep onset / wake state machine over a batch
    /// of retroactive predictions.
    private func processRetroPredictions(_ predictions: [(date: Date, prediction: SleepPrediction)]) {
        var localConsecutiveAsleep = 0
        var localConsecutiveAwake = 0
        var sleepDetected = false
        var onsetDate: Date? = nil
        var wakeDate: Date? = nil

        for (date, prediction) in predictions {
            if prediction.isAsleep {
                localConsecutiveAsleep += 1
                localConsecutiveAwake = 0

                if !sleepDetected && localConsecutiveAsleep >= consecutiveThreshold {
                    sleepDetected = true
                    // Walk back to when sleep likely started
                    let offset = Double(consecutiveThreshold - 1) * predictionInterval
                    onsetDate = date.addingTimeInterval(-offset)
                }
            } else {
                localConsecutiveAwake += 1
                localConsecutiveAsleep = 0

                if sleepDetected && localConsecutiveAwake >= wakeConsecutiveThreshold {
                    wakeDate = date
                    break // Found a complete sleep cycle
                }
            }
        }

        // If we found a complete sleep onset + wake cycle, record it
        if let onset = onsetDate, let wake = wakeDate {
            let duration = wake.timeIntervalSince(onset) / 3600.0

            // Only record if it looks like a real night of sleep (3–12 hours).
            // The upper bound guards against corrupt entries from long retroactive
            // analysis windows during development (e.g. a false 12h+ duration
            // written when CoreMotion had no prior baseline to work from).
            if duration >= 3.0 && duration <= 12.0 {
                estimatedSleepOnset = onset
                estimatedWakeTime = wake
                isAsleep = false

                // Update historical average
                let cal = Calendar.current
                let hour = cal.component(.hour, from: onset)
                let minute = cal.component(.minute, from: onset)
                let onsetHour = Double(hour) + Double(minute) / 60.0
                featureCollector.updateHistoricalAverage(newOnsetHour: onsetHour)

                // Record to sleep history
                SleepHistoryManager.shared.recordNight(
                    date: onset,
                    duration: duration,
                    onset: onset,
                    wake: wake
                )

                logSleepEvent(type: "retro_sleep_onset", at: onset)
                logSleepEvent(type: "retro_wake", at: wake)

                print("🔍 Retroactive: Sleep \(onset.formatted(date: .omitted, time: .shortened)) → \(wake.formatted(date: .omitted, time: .shortened)) (\(String(format: "%.1f", duration))h)")
            }
        } else if sleepDetected && wakeDate == nil {
            // Sleep was detected but no wake yet — user might still be sleeping
            // (background task ran in the middle of the night)
            if let onset = onsetDate {
                estimatedSleepOnset = onset
                isAsleep = true
                print("🔍 Retroactive: Sleep onset at \(onset.formatted(date: .omitted, time: .shortened)), still asleep")
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Live prediction (foreground only)
    // ─────────────────────────────────────────────────────────

    private func runLivePrediction() {
        let features = featureCollector.currentFeatures()
        let prediction = model.predict(features: features)

        latestPrediction = prediction
        sleepProbability = prediction.probability
        predictionHistory.append(prediction)

        if predictionHistory.count > 144 {
            predictionHistory.removeFirst(predictionHistory.count - 144)
        }

        // State machine for live predictions
        if prediction.isAsleep {
            consecutiveAsleepCount += 1
            consecutiveAwakeCount = 0

            if !isAsleep && consecutiveAsleepCount >= consecutiveThreshold {
                isAsleep = true

                let onsetOffset = Double(consecutiveThreshold - 1) * predictionInterval
                estimatedSleepOnset = Date().addingTimeInterval(-onsetOffset)
                estimatedWakeTime = nil

                let cal = Calendar.current
                let hour = cal.component(.hour, from: estimatedSleepOnset!)
                let minute = cal.component(.minute, from: estimatedSleepOnset!)
                featureCollector.updateHistoricalAverage(
                    newOnsetHour: Double(hour) + Double(minute) / 60.0
                )

                logSleepEvent(type: "sleep_onset", at: estimatedSleepOnset!)
                print("😴 Sleep onset detected at \(estimatedSleepOnset!.formatted(date: .omitted, time: .shortened))")
            }

        } else {
            consecutiveAwakeCount += 1
            consecutiveAsleepCount = 0

            if isAsleep && consecutiveAwakeCount >= wakeConsecutiveThreshold {
                isAsleep = false
                estimatedWakeTime = Date()

                logSleepEvent(type: "wake", at: estimatedWakeTime!)

                if let onset = estimatedSleepOnset {
                    let duration = estimatedWakeTime!.timeIntervalSince(onset) / 3600.0
                    print("☀️ Wake detected. Slept for \(String(format: "%.1f", duration)) hours")

                    SleepHistoryManager.shared.recordNight(
                        date: onset,
                        duration: duration,
                        onset: onset,
                        wake: estimatedWakeTime
                    )
                }
                consecutiveAsleepCount = 0
            }
        }

        #if DEBUG
        print("""
        🧠 Sleep: \(String(format: "%.0f%%", prediction.probability * 100)) \
        → \(prediction.isAsleep ? "ASLEEP" : "AWAKE") \
        (\(consecutiveAsleepCount)a/\(consecutiveAwakeCount)w)
        """)
        #endif
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Sleep duration helpers
    // ─────────────────────────────────────────────────────────

    var lastNightSleepDuration: Double? {
        guard let onset = estimatedSleepOnset,
              let wake = estimatedWakeTime else { return nil }
        return wake.timeIntervalSince(onset) / 3600.0
    }

    var lastNightSleepFormatted: String? {
        guard let duration = lastNightSleepDuration else { return nil }
        let hours = Int(duration)
        let minutes = Int((duration - Double(hours)) * 60)
        return "\(hours)h \(minutes)m"
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Logging
    // ─────────────────────────────────────────────────────────

    private func logSleepEvent(type: String, at date: Date) {
        trackingStore.appendSleepEvent(type: type, at: date)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Manual overrides
    // ─────────────────────────────────────────────────────────

    func manualSleepOnset() {
        let now = Date()
        isAsleep = true
        estimatedSleepOnset = now
        estimatedWakeTime = nil
        consecutiveAsleepCount = consecutiveThreshold

        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        featureCollector.updateHistoricalAverage(
            newOnsetHour: Double(hour) + Double(minute) / 60.0
        )

        logSleepEvent(type: "manual_sleep_onset", at: now)
        print("😴 Manual sleep onset at \(now.formatted(date: .omitted, time: .shortened))")
    }

    func manualWake() {
        guard isAsleep else { return }
        let now = Date()
        isAsleep = false
        estimatedWakeTime = now
        consecutiveAwakeCount = wakeConsecutiveThreshold

        logSleepEvent(type: "manual_wake", at: now)

        if let onset = estimatedSleepOnset {
            let duration = now.timeIntervalSince(onset) / 3600.0
            print("☀️ Manual wake. Slept for \(String(format: "%.1f", duration)) hours")

            SleepHistoryManager.shared.recordNight(
                date: onset,
                duration: duration,
                onset: onset,
                wake: now
            )
        }
    }

    func runPredictionNow() {
        runLivePrediction()
    }
}
