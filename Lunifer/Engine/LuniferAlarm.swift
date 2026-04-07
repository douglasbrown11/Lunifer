import Foundation
import Combine
import AlarmKit
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// ─────────────────────────────────────────────────────────────
// SECTION 1: ALARM METADATA
// ─────────────────────────────────────────────────────────────
// AlarmKit requires us to attach a "metadata" struct to every alarm.
// Think of metadata as a label we stick on the alarm that tells us
// WHY this alarm was set and what data was used to calculate it.
// This is also useful for the ML model — every alarm we log includes
// this context so the model can learn from it.
//
// "nonisolated" is a Swift 6 requirement — it just means this struct
// can be safely used from any part of the app without threading issues.

struct LuniferAlarmMetadata: AlarmMetadata {
    var scheduledWakeTime: Date      // The time we calculated the alarm for
    var calendarEventTitle: String   // The name of the first event tomorrow (e.g. "Team standup")
    var routineMinutes: Int          // How long the user's morning routine takes
    var commuteMinutes: Int          // How long their commute takes
}

// ─────────────────────────────────────────────────────────────
// SECTION 2: THE MAIN ALARM CLASS
// ─────────────────────────────────────────────────────────────
// This is the main class that controls everything alarm-related.
//
// "@MainActor" means all UI updates happen on the main thread (required for SwiftUI).
// "ObservableObject" means SwiftUI views can watch it and update automatically
//  when something changes (like when an alarm gets scheduled or fires).

@MainActor
class LuniferAlarm: ObservableObject {

    static let shared = LuniferAlarm()
    private let manager = AlarmManager.shared

    // ── @Published variables ──────────────────────────────────
    // "@Published" means: whenever these values change, any SwiftUI view
    // that's watching them will automatically refresh.
    // Think of it like a live feed — the UI always shows the current value.

    @Published var isAuthorized: Bool = false       // Has the user granted alarm permission?
    @Published var activeAlarms: [Alarm] = []       // List of currently scheduled alarms
    @Published var scheduledWakeTime: Date? = nil   // The time the next alarm is set for
    @Published var alertingAlarm: Alarm? = nil      // The alarm currently firing (nil = no alarm ringing)

    /// True when the user has explicitly denied alarm permission.
    /// Used by the dashboard to drive the "must allow" alert loop.
    var authorizationDenied: Bool { manager.authorizationState == .denied }

    // ── Sound helper ──────────────────────────────────────────
    // Reads the user's sound picker selection from UserDefaults and
    // returns the bare filename (no extension), which is what
    // AlarmPresentation.Sound.named(_:) expects.
    //
    // Falls back to "DeafultAlarm" if the key is missing (e.g. first
    // launch before the user has visited the sound picker).
    private var selectedAlarmSoundName: String {
        let filename = UserDefaults.standard.string(forKey: "selectedAlarmSound") ?? "DeafultAlarm.wav"
        return (filename as NSString).deletingPathExtension
    }

    // Tracks the first alarm time set each night so adaptive pushes
    // can be capped relative to it. Reset whenever a fresh base alarm is set.
    private var originalScheduledWakeTime: Date? = nil
    private var adaptiveTimer: Timer? = nil

    /// True once the alarm has been adjusted for the user's actual sleep
    /// onset. Prevents repeated adjustments on subsequent timer ticks.
    private var sleepOnsetAdjusted: Bool = false

    /// Maximum number of hours the alarm can be pushed past the original time.
    private let maxAdaptivePushHours: Double = 3.0

    // ─────────────────────────────────────────────────────────
    // SECTION 3: REQUESTING PERMISSION
    // ─────────────────────────────────────────────────────────
    // Before Lunifer can set any alarms, it must ask the user for permission.
    // iOS will show a popup saying "Lunifer wants to schedule alarms" with
    // Allow and Don't Allow buttons.
    // We call this function when the user finishes the survey.
    
    // "async" means this function can wait for things (like the user tapping Allow)
    // without freezing the whole app.

    func requestAuthorization() async {
       
        switch manager.authorizationState {

        case .notDetermined:
            // The user hasn't been asked yet — show the permission popup
            do {
                let state = try await manager.requestAuthorization()
                isAuthorized = state == .authorized
                print(isAuthorized ? "✅ Alarm permission granted" : "❌ Alarm permission denied")
            } catch {
                print("❌ Error requesting alarm permission: \(error.localizedDescription)")
                isAuthorized = false
            }

        case .authorized:
            // Already have permission — nothing to do
            isAuthorized = true

        case .denied:
            // User said no — we can't set alarms
            // In the UI we should show a message directing them to Settings
            isAuthorized = false
            print("❌ Alarm permission denied — tell user to enable in Settings")

        @unknown default:
            // Catch-all for any future permission states Apple might add
            isAuthorized = false
        }
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 4: SCHEDULING THE ALARM
    // ─────────────────────────────────────────────────────────
    // This is the main function that sets the alarm.
    // It gets called every night with the optimal wake time
    // calculated by LuniferEngine/LuniferCalendar.
    //
    // Parameters:
    //   date           — the exact time to fire the alarm
    //   eventTitle     — name of the first calendar event tomorrow
    //   routineMinutes — how long the user's morning routine takes (from survey)
    //   commuteMinutes — how long their commute takes (from survey)

    func scheduleAlarm(
        for date: Date,
        eventTitle: String = "your first event",
        routineMinutes: Int = 60,
        commuteMinutes: Int = 30
    ) async {

        // Reset adaptive state so this new schedule becomes the reference point.
        originalScheduledWakeTime = nil
        sleepOnsetAdjusted = false

        // Step 1: Make sure we have permission first
        // If we don't, ask for it. If user still says no, stop here.
        if !isAuthorized {
            await requestAuthorization()
        }
        guard isAuthorized else { return }

        // Step 2: Cancel any existing alarm so we don't have two alarms going off
        await cancelAlarm()

        // Step 3: Design what the alarm looks like when it fires
        // This creates the popup/banner the user sees on their lock screen
        // and in the Dynamic Island when the alarm goes off
        // Note: In iOS 26.1+, AlarmKit uses predefined button constants
        // instead of custom AlarmButton configurations
        let alert = AlarmPresentation.Alert(
            title: "Time to wake up",
            secondaryButton: AlarmButton(
                text: "Snooze",
                textColor: Color(red: 0.75, green: 0.65, blue: 1.0),
                systemImageName: "clock.arrow.circlepath"
            ),
            secondaryButtonBehavior: .countdown
        )

        // Step 4: Bundle the alert design + Lunifer's purple colour into "attributes"
        // AlarmAttributes is AlarmKit's way of packaging everything about
        // how the alarm looks and what data it carries
        let attributes = AlarmAttributes<LuniferAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, sound: .named(selectedAlarmSoundName)),  // The alert we designed above
            metadata: LuniferAlarmMetadata(                 // Our custom data attached to this alarm
                scheduledWakeTime: date,
                calendarEventTitle: eventTitle,
                routineMinutes: routineMinutes,
                commuteMinutes: commuteMinutes
            ),
            tintColor: Color(red: 0.55, green: 0.35, blue: 0.95)  // Purple tint for the UI
        )

        // Step 5: Actually schedule the alarm at the exact date/time
        // .fixed(date) means "fire at this exact moment"
        // (as opposed to .relative which fires after a countdown)
        do {
            let _ = try await manager.schedule(
                id: UUID(),             // A unique ID for this alarm — UUID generates a random one
                configuration: .alarm(
                    schedule: .fixed(date),   // Fire at this exact time
                    attributes: attributes    // Using the design + data we set up above
                )
            )

            // If we got here without an error, the alarm was successfully scheduled
            scheduledWakeTime = date
            print("✅ Alarm set for \(date.formatted(date: .omitted, time: .shortened))")

            // Log the scheduling event for the ML model
            AlarmBehaviourLogger.shared.logScheduled(for: date)

        } catch {
            // Something went wrong — print the error for debugging in Xcode console
            print("❌ Failed to schedule alarm: \(error.localizedDescription)")
        }
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 4b: ADDED ALARM
    // ─────────────────────────────────────────────────────────
    // Schedules a second, independently managed alarm set by the user.
    // Stored separately from the main Lunifer alarm so cancelling
    // one does not affect the other.

    @Published var addedAlarmID: UUID? = nil

    func scheduleAddedAlarm(for date: Date) async {
        if !isAuthorized { await requestAuthorization() }
        guard isAuthorized else { return }

        // Cancel any previously added alarm first
        await cancelAddedAlarm()

        let alert = AlarmPresentation.Alert(
            title: "Added Alarm",
            secondaryButton: AlarmButton(
                text: "Snooze",
                textColor: Color(red: 0.75, green: 0.65, blue: 1.0),
                systemImageName: "clock.arrow.circlepath"
            ),
            secondaryButtonBehavior: .countdown
        )

        let attributes = AlarmAttributes<LuniferAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, sound: .named(selectedAlarmSoundName)),
            metadata: LuniferAlarmMetadata(
                scheduledWakeTime: date,
                calendarEventTitle: "",
                routineMinutes: 0,
                commuteMinutes: 0
            ),
            tintColor: Color(red: 0.55, green: 0.35, blue: 0.95)
        )

        let id = UUID()
        do {
            let _ = try await manager.schedule(
                id: id,
                configuration: .alarm(
                    schedule: .fixed(date),
                    attributes: attributes
                )
            )
            addedAlarmID = id
            print("✅ Added alarm set for \(date.formatted(date: .omitted, time: .shortened))")
        } catch {
            print("❌ Failed to schedule added alarm: \(error.localizedDescription)")
        }
    }

    func cancelAddedAlarm() async {
        guard let id = addedAlarmID else { return }
        try? manager.cancel(id: id)
        addedAlarmID = nil
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 5: CANCELLING THE ALARM
    // ─────────────────────────────────────────────────────────
    // Cancels all active Lunifer alarms.
    // Called before scheduling a new alarm, or if the user
    // manually turns off the alarm from the dashboard.

    func cancelAlarm() async {
        for alarm in activeAlarms {
            do {
                try manager.cancel(id: alarm.id)  // Tell AlarmKit to remove this alarm
            } catch {
                print("❌ Failed to cancel alarm: \(error.localizedDescription)")
            }
        }
        scheduledWakeTime = nil  // Clear the displayed wake time in the UI
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 6: MONITORING ALARM STATE
    // ─────────────────────────────────────────────────────────
    // This function runs continuously in the background from the moment
    // the app opens. It listens for any changes to our alarms —
    // like when a new one is scheduled, cancelled, or fires.
    //
    // "for await" means: keep looping every time AlarmKit sends us an update.
    // It's like subscribing to a live news feed.
    //
    // Add this to ContentView.swift:
    // .task { await LuniferAlarm.shared.startMonitoring() }

    func startMonitoring() async {
        for await alarms in manager.alarmUpdates {

            // Update our local list of active alarms so the UI stays in sync
            activeAlarms = alarms

            // Check if any alarm is currently firing
            let firing = alarms.first(where: { if case .alerting = $0.state { return true }; return false })

            if let firing {
                // Only log when the alarm first starts firing, not on every update
                if alertingAlarm == nil {
                    AlarmBehaviourLogger.shared.logAlarmFired(at: Date())
                }
                alertingAlarm = firing
            } else {
                alertingAlarm = nil
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 7: SNOOZE
    // ─────────────────────────────────────────────────────────
    // Dismisses the current alarm and reschedules it for now + snoozeMinutes.

    func snooze(minutes: Int) async {
        if let alarm = alertingAlarm {
            try? manager.cancel(id: alarm.id)
        }
        AlarmBehaviourLogger.shared.logSnooze(at: Date())
        alertingAlarm = nil
        let snoozeDate = Date().addingTimeInterval(Double(minutes) * 60)
        await scheduleAlarm(for: snoozeDate)
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 8: STOP ALARM
    // ─────────────────────────────────────────────────────────
    // Dismisses the currently firing alarm and logs the dismiss event.

    func stopAlarm() async {
        if let alarm = alertingAlarm {
            try? manager.cancel(id: alarm.id)
        }
        AlarmBehaviourLogger.shared.logDismiss(at: Date())
        alertingAlarm = nil
        scheduledWakeTime = nil
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 9: ADAPTIVE RESCHEDULING
    // ─────────────────────────────────────────────────────────
    // If the sleep tracker detects the user is still awake after
    // their recommended bedtime, the alarm is pushed forward to
    // preserve their full sleep duration from the current moment.
    //
    // ALGORITHM (runs every 5 minutes):
    //   • User is NOT asleep
    //   • Current time is past bedtime (alarm − sleepDuration)
    //   • There is a scheduled alarm
    //   → newWakeTime = now + sleepDuration
    //   → if newWakeTime > currentAlarm → reschedule
    //
    // CAP: The alarm will not be pushed more than 3 hours past the
    // original scheduled time so it doesn't drift indefinitely.

    /// Starts the adaptive timer. Call this from the dashboard on load.
    func startAdaptiveRescheduling() {
        adaptiveTimer?.invalidate()
        adaptiveTimer = Timer.scheduledTimer(
            withTimeInterval: 5 * 60,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkAndAdaptAlarm()
            }
        }
    }

    func stopAdaptiveRescheduling() {
        adaptiveTimer?.invalidate()
        adaptiveTimer = nil
    }

    private func checkAndAdaptAlarm() async {
        // Only run while Lunifer is enabled
        guard UserDefaults.standard.bool(forKey: "luniferEnabled") else { return }

        // Need a scheduled alarm to adjust
        guard let currentAlarm = scheduledWakeTime else { return }

        // ── Derive sleep duration from saved survey answers ──
        let answers = SurveyAnswers.loadFromDefaults()
        let sleepHours: Double
        if let a = answers {
            sleepHours = a.sleep.auto
                ? SleepDurationModel.baselineForAge(a.age)
                : Double(a.sleep.hours) + Double(a.sleep.minutes) / 60.0
        } else {
            sleepHours = 8.0
        }

        let now = Date()
        let expectedBedtime = currentAlarm.addingTimeInterval(-sleepHours * 3600)

        // ── Derive routine & commute for calendar constraint ─
        let routineMins: Int
        let commuteMins: Int
        if let a = answers {
            routineMins = a.routine.auto
                ? 60
                : a.routine.hours * 60 + a.routine.minutes
            if a.lifestyle == "student" || a.lifestyle == "commuter" {
                commuteMins = a.commute.auto
                    ? 30
                    : a.commute.hours * 60 + a.commute.minutes
            } else {
                commuteMins = 0
            }
        } else {
            routineMins = 60
            commuteMins = 30
        }

        // ── Calendar constraint ──────────────────────────────
        // If the user has a timed event tomorrow, calculate the
        // latest alarm that still lets them complete their morning
        // routine and commute before the event starts.
        await CalendarManager.shared.fetchEvents()
        let latestAllowedAlarm: Date?
        if let firstEvent = CalendarManager.shared.firstEventTomorrow {
            let bufferSeconds = Double(routineMins + commuteMins) * 60
            latestAllowedAlarm = firstEvent.startDate.addingTimeInterval(-bufferSeconds)
        } else {
            latestAllowedAlarm = nil
        }

        // Helper: clamp a proposed alarm so it respects both the
        // 3-hour adaptive cap AND the calendar constraint.
        func clamped(_ proposed: Date) -> Date {
            var result = proposed
            // Don't push more than 3 hours past the original alarm
            if let original = originalScheduledWakeTime {
                let cap = original.addingTimeInterval(maxAdaptivePushHours * 3600)
                result = min(result, cap)
            }
            // Don't push past the point where routine + commute
            // would cause the user to miss their first event
            if let latest = latestAllowedAlarm {
                result = min(result, latest)
            }
            return result
        }

        var newWakeTime: Date? = nil

        if SleepTracker.shared.isAsleep {
            // ── PATH A: User fell asleep ─────────────────────
            // Adjust the alarm once based on when they actually
            // fell asleep compared to the expected bedtime.
            //
            // Example — late:
            //   Expected bedtime 11:30 PM, alarm 7:30 AM
            //   Fell asleep at 11:45 PM (+15 min)
            //   → New alarm 7:45 AM (preserves full sleep)
            //
            // Example — early:
            //   Expected bedtime 11:30 PM, alarm 7:30 AM
            //   Fell asleep at 11:00 PM (−30 min)
            //   → New alarm 7:00 AM (wake up earlier, still full sleep)

            guard !sleepOnsetAdjusted else { return }

            // estimatedSleepOnset becomes available after ~15 min
            // of consecutive sleep predictions. If it's not set yet
            // we'll catch it on the next 5-minute tick.
            guard let onset = SleepTracker.shared.estimatedSleepOnset else { return }

            // Delta: positive = slept later than expected, negative = earlier
            let delta = onset.timeIntervalSince(expectedBedtime)
            // Apply delta to the ORIGINAL alarm, not the current one —
            // Path B may have already pushed currentAlarm forward while
            // the user was still awake, so using currentAlarm here would
            // double-count the late-sleep offset.
            let baseAlarm = originalScheduledWakeTime ?? currentAlarm
            let proposed = baseAlarm.addingTimeInterval(delta)

            // On the first adjustment, snapshot the original alarm
            if originalScheduledWakeTime == nil {
                originalScheduledWakeTime = currentAlarm
            }

            let adjusted = clamped(proposed)

            // Only reschedule if the shift is meaningful (≥ 2 minutes)
            guard abs(adjusted.timeIntervalSince(currentAlarm)) >= 2 * 60 else {
                sleepOnsetAdjusted = true
                return
            }

            newWakeTime = adjusted
            // Flag is set BEFORE the schedule call; it gets saved/restored
            // below because scheduleAlarm() resets adaptive state.
            sleepOnsetAdjusted = true

        } else {
            // ── PATH B: User is still awake past bedtime ─────
            // Push the alarm later so they still get a full night
            // of sleep from the moment they eventually fall asleep.

            // Only act after bedtime has passed
            guard now > expectedBedtime else { return }

            // Minimum wake time if the user fell asleep right now
            let minimumWakeTime = now.addingTimeInterval(sleepHours * 3600)

            // Current alarm already gives enough sleep — nothing to do
            guard minimumWakeTime > currentAlarm else { return }

            // On the first push, snapshot the original alarm
            if originalScheduledWakeTime == nil {
                originalScheduledWakeTime = currentAlarm
            }

            let adjusted = clamped(minimumWakeTime)

            // Skip if the change is less than 5 minutes
            guard adjusted.timeIntervalSince(currentAlarm) >= 5 * 60 else { return }

            newWakeTime = adjusted
        }

        guard let newTime = newWakeTime else { return }

        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        let arrow = newTime > currentAlarm ? "→" : "←"
        print("⏰ Adaptive: \(fmt.string(from: currentAlarm)) \(arrow) \(fmt.string(from: newTime))")

        // Preserve adaptive state across the internal reschedule —
        // scheduleAlarm() resets these, so save and restore them.
        let savedOriginal = originalScheduledWakeTime!
        let savedOnsetFlag = sleepOnsetAdjusted
        await scheduleAlarm(for: newTime)
        originalScheduledWakeTime = savedOriginal
        sleepOnsetAdjusted = savedOnsetFlag
    }
}

// ─────────────────────────────────────────────────────────────
// SECTION 7: BEHAVIOUR LOGGER
// ─────────────────────────────────────────────────────────────
// Records inferences about the user's alarm behaviour — not raw events,
// but derived conclusions about whether the alarm was well-timed.
//
// Instead of storing every individual tap, we accumulate state across
// one alarm session (fire → snoozes → final dismiss) and then save
// a single inference document to Firestore when the session ends.
//
// The inference answers: "Was this alarm set at the right time?"
//
//   snoozeCount == 0 → alarm was on time
//   snoozeCount 1–2  → alarm was slightly early
//   snoozeCount 3+   → alarm was too early
//   wokeBeforeAlarm  → alarm was too late (or sleep need was lower)
//
// Over 30+ nights this gives the ML model a clean signal to personalise
// future alarm times by day of week and sleep pattern.

class AlarmBehaviourLogger {

    static let shared = AlarmBehaviourLogger()

    // ── Session state ─────────────────────────────────────────
    // Tracks the current alarm session from fire → dismiss.

    private var scheduledWakeTime: Date? = nil
    private var alarmFiredAt: Date?      = nil
    private var snoozeCount: Int         = 0

    // ── Lifecycle hooks ───────────────────────────────────────

    /// Called when a new alarm is scheduled for the night.
    func logScheduled(for date: Date) {
        scheduledWakeTime = date
        alarmFiredAt      = nil
        snoozeCount       = 0
        print("📅 Alarm scheduled for \(date.formatted(date: .omitted, time: .shortened))")
    }

    /// Called when the alarm fires. Starts a new session.
    func logAlarmFired(at date: Date) {
        alarmFiredAt = date
        snoozeCount  = 0
        print("🔔 Alarm fired at \(date.formatted(date: .omitted, time: .shortened))")
    }

    /// Called each time the user taps Snooze.
    func logSnooze(at date: Date) {
        snoozeCount += 1
        print("😴 Snooze #\(snoozeCount) at \(date.formatted(date: .omitted, time: .shortened))")
    }

    /// Called when the user taps Dismiss. Finalises the session
    /// and saves the inference to Firestore.
    func logDismiss(at date: Date) {
        saveInference(outcome: "dismissed", at: date)
        resetSession()
    }

    /// Called when the user woke before the alarm fired.
    /// (Used when HealthKit integration is added later.)
    func logWokeBeforeAlarm(at date: Date) {
        saveInference(outcome: "woke_before_alarm", at: date)
        resetSession()
    }

    // ── Inference logic ───────────────────────────────────────

    /// Derives a conclusion about alarm accuracy and saves it to Firestore.
    /// This single document per morning is what the ML model reads.
    private func saveInference(outcome: String, at date: Date) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Derive how well the alarm was timed from snooze behaviour
        let assessment: String
        switch (outcome, snoozeCount) {
        case ("woke_before_alarm", _): assessment = "too_late"
        case (_, 0):                   assessment = "on_time"
        case (_, 1...2):               assessment = "slightly_early"
        default:                       assessment = "too_early"
        }

        var inference: [String: Any] = [
            "date":        date,
            "dayOfWeek":   Calendar.current.component(.weekday, from: date),
            "snoozeCount": snoozeCount,
            "outcome":     outcome,
            "assessment":  assessment  // The key signal for the ML model
        ]
        if let scheduled = scheduledWakeTime { inference["scheduledWakeTime"] = scheduled }
        if let fired     = alarmFiredAt      { inference["alarmFiredAt"]      = fired     }

        Firestore.firestore()
            .collection("users").document(uid)
            .collection("alarmInferences")
            .addDocument(data: inference) { error in
                if let error {
                    print("❌ Failed to save alarm inference: \(error.localizedDescription)")
                } else {
                    print("✅ Alarm inference saved — assessment: \(assessment), snoozes: \(self.snoozeCount)")
                }
            }
    }

    private func resetSession() {
        scheduledWakeTime = nil
        alarmFiredAt      = nil
        snoozeCount       = 0
    }
}
