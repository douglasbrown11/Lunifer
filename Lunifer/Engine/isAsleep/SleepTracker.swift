import Foundation
import Combine
import SwiftUI

// ─────────────────────────────────────────────────────────────
// SleepTracker
// ─────────────────────────────────────────────────────────────
// The orchestrator that ties everything together. It:
//
//   1. Owns the SleepFeatureCollector (data in)
//   2. Owns the SleepPredictionModel (prediction logic)
//   3. Runs predictions every 5 minutes
//   4. Detects sleep onset / wake transitions
//   5. Logs sleep events for the historical average
//   6. Exposes state for the dashboard UI
//
// USAGE:
// In ContentView.swift, add alongside LuniferAlarm:
//
//   @StateObject private var sleepTracker = SleepTracker()
//
//   .task {
//       await sleepTracker.startTracking()
//   }
//   .environmentObject(sleepTracker)
//
// Then in LuniferDashboard or anywhere:
//
//   @EnvironmentObject var sleepTracker: SleepTracker
//   // sleepTracker.isAsleep
//   // sleepTracker.sleepProbability
//   // sleepTracker.estimatedSleepOnset

@MainActor
final class SleepTracker: ObservableObject {

    // MARK: - Published state for the UI

    /// Current prediction: is the user asleep?
    @Published private(set) var isAsleep: Bool = false

    /// Current probability (0–1) that the user is asleep.
    @Published private(set) var sleepProbability: Double = 0

    /// The estimated time the user fell asleep tonight.
    /// nil if they haven't fallen asleep yet (or just woke up).
    @Published private(set) var estimatedSleepOnset: Date? = nil

    /// The estimated time the user woke up.
    /// nil if they're still asleep or haven't slept yet.
    @Published private(set) var estimatedWakeTime: Date? = nil

    /// The latest full prediction with all feature scores,
    /// useful for debugging or a "sleep insights" screen.
    @Published private(set) var latestPrediction: SleepPrediction? = nil

    /// History of tonight's predictions, for charting sleep probability
    /// over time if we want to show a graph.
    @Published private(set) var predictionHistory: [SleepPrediction] = []

    // MARK: - Internal components

    let featureCollector = SleepFeatureCollector()
    private var model = SleepPredictionModel()
    private var predictionTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// How often to run a prediction (in seconds).
    /// 5 minutes is a good balance between accuracy and battery.
    private let predictionInterval: TimeInterval = 5 * 60

    /// Number of consecutive "asleep" predictions required before
    /// we declare sleep onset. This prevents a single false positive
    /// (e.g. the user set their phone down for 10 minutes) from
    /// triggering a premature sleep detection.
    private let consecutiveThreshold = 3

    /// Rolling count of consecutive asleep predictions.
    private var consecutiveAsleepCount = 0

    /// Rolling count of consecutive awake predictions (for wake detection).
    private var consecutiveAwakeCount = 0
    private let wakeConsecutiveThreshold = 2

    // MARK: - Lifecycle

    /// Start the sleep tracking system. Call from ContentView .task.
    func startTracking() async {
        featureCollector.startCollecting()

        // Run predictions on a timer
        predictionTimer = Timer.scheduledTimer(
            withTimeInterval: predictionInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runPrediction()
            }
        }

        // Run an initial prediction after a short delay
        // to let the feature collector gather first readings
        try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
        runPrediction()
    }

    /// Stop tracking. Call when no longer needed.
    func stopTracking() {
        featureCollector.stopCollecting()
        predictionTimer?.invalidate()
        predictionTimer = nil
    }

    // MARK: - Prediction loop

    private func runPrediction() {
        let features = featureCollector.currentFeatures()
        let prediction = model.predict(features: features)

        latestPrediction = prediction
        sleepProbability = prediction.probability
        predictionHistory.append(prediction)

        // Cap history to last 12 hours (144 entries at 5-min intervals)
        if predictionHistory.count > 144 {
            predictionHistory.removeFirst(predictionHistory.count - 144)
        }

        // ── State machine: detect sleep onset and wake ───────

        if prediction.isAsleep {
            consecutiveAsleepCount += 1
            consecutiveAwakeCount = 0

            // Require N consecutive "asleep" predictions to confirm sleep onset
            if !isAsleep && consecutiveAsleepCount >= consecutiveThreshold {
                // SLEEP ONSET DETECTED
                isAsleep = true

                // The actual onset was approximately when the first
                // consecutive "asleep" prediction happened, not now.
                // Walk back by (consecutiveThreshold - 1) intervals.
                let onsetOffset = Double(consecutiveThreshold - 1) * predictionInterval
                estimatedSleepOnset = Date().addingTimeInterval(-onsetOffset)
                estimatedWakeTime = nil

                // Update the historical average
                let cal = Calendar.current
                let hour = cal.component(.hour, from: estimatedSleepOnset!)
                let minute = cal.component(.minute, from: estimatedSleepOnset!)
                let onsetHour = Double(hour) + Double(minute) / 60.0
                featureCollector.updateHistoricalAverage(newOnsetHour: onsetHour)

                // Log the event
                logSleepEvent(type: "sleep_onset", at: estimatedSleepOnset!)

                print("😴 Sleep onset detected at \(estimatedSleepOnset!.formatted(date: .omitted, time: .shortened))")
            }

        } else {
            consecutiveAwakeCount += 1
            consecutiveAsleepCount = 0

            // Detect waking up
            if isAsleep && consecutiveAwakeCount >= wakeConsecutiveThreshold {
                // WAKE DETECTED
                isAsleep = false
                estimatedWakeTime = Date()

                logSleepEvent(type: "wake", at: estimatedWakeTime!)

                if let onset = estimatedSleepOnset {
                    let duration = estimatedWakeTime!.timeIntervalSince(onset) / 3600.0
                    print("☀️ Wake detected. Slept for \(String(format: "%.1f", duration)) hours")
                }

                // Reset for next night
                consecutiveAsleepCount = 0
            }
        }

        // Debug logging (remove or gate behind a debug flag in production)
        #if DEBUG
        print("""
        🧠 Sleep prediction: \(String(format: "%.1f%%", prediction.probability * 100)) \
        [inact=\(String(format: "%.2f", prediction.featureScores.inactivity)) \
        motion=\(String(format: "%.2f", prediction.featureScores.motion)) \
        time=\(String(format: "%.2f", prediction.featureScores.timeOfDay)) \
        unlock=\(String(format: "%.2f", prediction.featureScores.unlockCadence)) \
        focus=\(String(format: "%.2f", prediction.featureScores.sleepFocus)) \
        hist=\(String(format: "%.2f", prediction.featureScores.historicalPrior))] \
        → \(prediction.isAsleep ? "ASLEEP" : "AWAKE") \
        (consecutive: \(consecutiveAsleepCount)a/\(consecutiveAwakeCount)w)
        """)
        #endif
    }

    // MARK: - Sleep duration

    /// Estimated sleep duration for last night, in hours.
    /// Returns nil if we don't have both onset and wake data.
    var lastNightSleepDuration: Double? {
        guard let onset = estimatedSleepOnset,
              let wake = estimatedWakeTime else { return nil }
        return wake.timeIntervalSince(onset) / 3600.0
    }

    /// Formatted string like "7h 32m" for display on the dashboard.
    var lastNightSleepFormatted: String? {
        guard let duration = lastNightSleepDuration else { return nil }
        let hours = Int(duration)
        let minutes = Int((duration - Double(hours)) * 60)
        return "\(hours)h \(minutes)m"
    }

    // MARK: - Logging

    /// Saves sleep events to UserDefaults for now.
    /// Can be extended to write to Firestore via AlarmBehaviourLogger
    /// once the Firebase integration is fully wired.
    private func logSleepEvent(type: String, at date: Date) {
        // Store in UserDefaults as a simple log
        var log = UserDefaults.standard.array(forKey: "lunifer_sleep_log") as? [[String: Any]] ?? []
        log.append([
            "type": type,
            "timestamp": date.timeIntervalSince1970,
            "dayOfWeek": Calendar.current.component(.weekday, from: date)
        ])

        // Keep last 90 days of events
        if log.count > 180 {
            log = Array(log.suffix(180))
        }
        UserDefaults.standard.set(log, forKey: "lunifer_sleep_log")
    }

    // MARK: - Manual override / testing

    /// Force a prediction right now (useful for testing or
    /// when the user explicitly says "I'm going to sleep").
    func runPredictionNow() {
        runPrediction()
    }

    /// Manually mark sleep onset (e.g. user taps "I'm going to sleep").
    /// This also feeds the historical average so the model learns.
    func manualSleepOnset() {
        let now = Date()
        isAsleep = true
        estimatedSleepOnset = now
        estimatedWakeTime = nil
        consecutiveAsleepCount = consecutiveThreshold

        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        featureCollector.updateHistoricalAverage(newOnsetHour: Double(hour) + Double(minute) / 60.0)

        logSleepEvent(type: "manual_sleep_onset", at: now)
        print("😴 Manual sleep onset at \(now.formatted(date: .omitted, time: .shortened))")
    }

    /// Manually mark wake (e.g. user dismisses alarm or opens app in morning).
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
        }
    }
}
