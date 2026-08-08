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

        // A deliberate phone pickup in the morning near the alarm is a near-certain
        // "the user is awake now" signal. Finalize last night immediately so Sleep
        // Insights updates the moment the app is opened, rather than waiting for the
        // passive state machine to confirm a wake (which is slow right after waking).
        await confirmWakeFromMorningPickup()

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

        // No earliestBeginDate — iOS can run this immediately
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

        // Resolve any armed morning-routine session — the user's departure may
        // have happened while the app was suspended.
        if let answers = SurveyAnswers.loadFromDefaults() {
            MorningRoutineEstimator.shared.refresh(answers: answers)
        }

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

        // Throttle: don't re-run if the analysis actually ran within the last 10
        // minutes. This uses a dedicated "last run" timestamp rather than the
        // coverage checkpoint (analysisStart), so pinning the checkpoint back to a
        // still-asleep onset below does not cause the analysis to fire every tick.
        if let lastRun = trackingStore.lastRetroactiveRunDate(),
           now.timeIntervalSince(lastRun) < 10 * 60 { return }

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

        // Process the retroactive predictions through the state machine. When it
        // ends still-asleep (onset found, no wake yet), it returns that onset.
        let pendingOnset = processRetroPredictions(retroPredictions)

        // Record that the analysis ran (throttle), then advance the coverage
        // checkpoint. If we're still asleep, keep the checkpoint at/just before the
        // detected onset so the NEXT window still spans the full night and can
        // complete the onset→wake cycle. Advancing to `now` here (the old behaviour)
        // orphaned the onset, so the night was never recorded once the wake happened.
        trackingStore.setLastRetroactiveRunDate(now)
        if let pendingOnset {
            trackingStore.setLastRetroactiveAnalysisDate(min(pendingOnset, now))
        } else {
            trackingStore.setLastRetroactiveAnalysisDate(now)
        }
    }

    /// Runs the sleep onset / wake state machine over a batch of retroactive
    /// predictions. Returns the detected sleep onset when the batch ends
    /// still-asleep (onset found but no confirmed wake yet), so the caller can hold
    /// the coverage checkpoint before it; returns nil otherwise (complete cycle
    /// recorded, or no onset found).
    @discardableResult
    private func processRetroPredictions(_ predictions: [(date: Date, prediction: SleepPrediction)]) -> Date? {
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
                featureCollector.updateHistoricalAverage(newOnsetHour: onsetHour, for: onset)

                // Record to sleep history
                SleepHistoryManager.shared.recordNight(
                    date: onset,
                    duration: duration,
                    onset: onset,
                    wake: wake
                )
                LuniferAlarm.shared.recordWokeBeforeAlarmIfNeeded(at: wake)
                if let answers = SurveyAnswers.loadFromDefaults() {
                    MorningRoutineEstimator.shared.handleWakeDetected(at: wake, answers: answers)
                }

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
                // Surface the pending onset so runRetroactiveAnalysis holds the
                // coverage checkpoint at/before it (prevents orphaning the night).
                return onset
            }
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Morning phone-pickup fast path
    // ─────────────────────────────────────────────────────────
    // The passive state machine can be slow to CONFIRM a wake: it needs a
    // sustained awake signal, and pre-dawn time-of-day still scores as likely
    // sleep, so a completed night can fail to land in Sleep Insights the moment
    // the user gets up — especially when they wake before their alarm. A
    // deliberate phone pickup in the morning near the alarm is a near-certain
    // "awake now" signal, so this path treats the pickup as the wake and finalizes
    // last night immediately. Only the WAKE is shortcut — the onset it pairs with
    // still comes from the full prediction model (or its retroactive re-run, or the
    // historical average as a last resort), so onset accuracy is unchanged.
    //
    // Guarded so a middle-of-the-night phone check can't be logged as a wake:
    //   • Only near the scheduled alarm's clock time projected onto today
    //     ([alarm − 2h, alarm + 3h]); with no alarm, only in a morning band.
    //   • Only records a physically plausible 3–12h night.
    //   • Records at most once per calendar day (dedupe).

    /// Finalizes last night from a morning phone pickup. Safe to call on every app
    /// open / foreground; it no-ops outside the morning window, without an onset, or
    /// once it has already recorded a wake today.
    func confirmWakeFromMorningPickup() async {
        let now = Date()

        // Dedupe — at most one morning-pickup wake per calendar day.
        let dayKey = Self.dayKey(for: now)
        if trackingStore.lastMorningWakeRecordedDay() == dayKey { return }

        // Only in the morning, near the alarm.
        guard isWithinMorningWakeWindow(now: now) else { return }

        // Resolve last night's onset from the full model (with fallbacks).
        guard let onset = await resolveOnsetForMorningWake(now: now) else { return }

        let duration = now.timeIntervalSince(onset) / 3600.0
        guard duration >= 3.0, duration <= 12.0 else { return }

        // Update in-memory state and run the SAME tail the normal wake path uses.
        estimatedSleepOnset    = onset
        estimatedWakeTime      = now
        isAsleep               = false
        consecutiveAwakeCount  = wakeConsecutiveThreshold
        consecutiveAsleepCount = 0

        let cal = Calendar.current
        let onsetHour = Double(cal.component(.hour, from: onset))
            + Double(cal.component(.minute, from: onset)) / 60.0
        featureCollector.updateHistoricalAverage(newOnsetHour: onsetHour, for: onset)

        SleepHistoryManager.shared.recordNight(
            date: now, duration: duration, onset: onset, wake: now
        )
        LuniferAlarm.shared.recordWokeBeforeAlarmIfNeeded(at: now)
        if let answers = SurveyAnswers.loadFromDefaults() {
            MorningRoutineEstimator.shared.handleWakeDetected(at: now, answers: answers)
        }
        logSleepEvent(type: "morning_pickup_wake", at: now)

        trackingStore.setLastMorningWakeRecordedDay(dayKey)
        print("☀️ Morning pickup wake recorded — onset \(onset.formatted(date: .omitted, time: .shortened)), \(String(format: "%.1f", duration))h")
    }

    /// True when `now` sits in the morning window where a phone pickup should count
    /// as a wake. Preferred gate is proximity to the scheduled alarm's time-of-day
    /// projected onto today ([alarm − 2h, alarm + 3h]) — projecting the clock time
    /// means it still works after the scheduled alarm has rolled to tomorrow's date.
    /// With no scheduled alarm it falls back to a plain morning band (3 AM–11 AM).
    private func isWithinMorningWakeWindow(now: Date) -> Bool {
        let cal = Calendar.current
        if let alarm = LuniferAlarm.shared.scheduledWakeTime {
            let h = cal.component(.hour, from: alarm)
            let m = cal.component(.minute, from: alarm)
            if let alarmToday = cal.date(bySettingHour: h, minute: m, second: 0, of: now) {
                let start = alarmToday.addingTimeInterval(-2 * 3600)
                let end   = alarmToday.addingTimeInterval(3 * 3600)
                return now >= start && now <= end
            }
        }
        let hour = cal.component(.hour, from: now)
        return hour >= 3 && hour < 11
    }

    /// Resolves last night's sleep onset for the fast path, in priority order:
    ///   1. The model's own `estimatedSleepOnset`, if fresh (< 14h old, before now).
    ///   2. A retroactive re-run of the FULL prediction model over the last 14h.
    ///   3. The stored historical average onset mapped onto last night.
    /// Returns nil if none yields a plausible pre-`now` onset.
    private func resolveOnsetForMorningWake(now: Date) async -> Date? {
        // 1. Fresh model output.
        if let onset = estimatedSleepOnset,
           onset < now,
           now.timeIntervalSince(onset) <= 14 * 3600 {
            return onset
        }

        // 2. Full-model retroactive scan of the night (NOT a motion-only heuristic —
        //    reconstructFeatures + model.predict is the same model used everywhere).
        let windowStart = now.addingTimeInterval(-14 * 3600)
        let motionHistory = await featureCollector.queryMotionHistory(from: windowStart, to: now)
        if let onset = detectOnset(from: windowStart, to: now, motionHistory: motionHistory),
           onset < now {
            return onset
        }

        // 3. Historical average onset mapped onto last night.
        if let onset = historicalAverageOnset(for: now), onset < now {
            return onset
        }
        return nil
    }

    /// Steps the full prediction model across a window in 5-minute increments and
    /// returns the first detected sleep onset (3 consecutive asleep predictions,
    /// walked back to the likely start). Same model + threshold as the live and
    /// retroactive paths — this is not a motion-only shortcut.
    private func detectOnset(from start: Date, to end: Date, motionHistory: [MotionSample]) -> Date? {
        var t = start
        let step: TimeInterval = 5 * 60
        var consecutiveAsleep = 0
        while t <= end {
            let features = featureCollector.reconstructFeatures(at: t, motionHistory: motionHistory)
            if model.predict(features: features).isAsleep {
                consecutiveAsleep += 1
                if consecutiveAsleep >= consecutiveThreshold {
                    let offset = Double(consecutiveThreshold - 1) * step
                    return t.addingTimeInterval(-offset)
                }
            } else {
                consecutiveAsleep = 0
            }
            t = t.addingTimeInterval(step)
        }
        return nil
    }

    /// Builds a concrete onset Date for last night from the stored rolling-average
    /// onset hour (weekday/weekend). Evening onsets (hour ≥ 12) are placed on
    /// yesterday; after-midnight onsets (hour < 12) on today, so the result lands
    /// before a morning wake. Picks the bucket from the previous evening's weekday.
    private func historicalAverageOnset(for now: Date) -> Date? {
        let cal = Calendar.current
        func build(_ avgHour: Double?) -> Date? {
            guard let avgHour else { return nil }
            let h = Int(avgHour)
            let m = Int((avgHour - Double(h)) * 60)
            let baseDay = h >= 12
                ? (cal.date(byAdding: .day, value: -1, to: now) ?? now)
                : now
            return cal.date(bySettingHour: h, minute: m, second: 0, of: baseDay)
        }
        // Weekend sleep = the onset evening was Fri (6) or Sat (7).
        let yesterday = cal.date(byAdding: .day, value: -1, to: now) ?? now
        let wd = cal.component(.weekday, from: yesterday)
        let preferWeekend = (wd == 6 || wd == 7)
        let preferred = preferWeekend
            ? featureCollector.historicalAvgSleepOnsetWeekend
            : featureCollector.historicalAvgSleepOnsetWeekday
        return build(preferred)
            ?? build(featureCollector.historicalAvgSleepOnsetWeekday)
            ?? build(featureCollector.historicalAvgSleepOnsetWeekend)
    }

    /// "yyyy-MM-dd" key for the morning-wake dedupe.
    private static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
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
                    newOnsetHour: Double(hour) + Double(minute) / 60.0,
                    for: estimatedSleepOnset!
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
                    if let wake = estimatedWakeTime {
                        LuniferAlarm.shared.recordWokeBeforeAlarmIfNeeded(at: wake)
                        if let answers = SurveyAnswers.loadFromDefaults() {
                            MorningRoutineEstimator.shared.handleWakeDetected(at: wake, answers: answers)
                        }
                    }
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
            newOnsetHour: Double(hour) + Double(minute) / 60.0,
            for: now
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
            LuniferAlarm.shared.recordWokeBeforeAlarmIfNeeded(at: now)
            if let answers = SurveyAnswers.loadFromDefaults() {
                MorningRoutineEstimator.shared.handleWakeDetected(at: now, answers: answers)
            }
        }
    }

    func runPredictionNow() {
        runLivePrediction()
    }
}
