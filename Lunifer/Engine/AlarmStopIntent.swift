import Foundation
import AppIntents

// ─────────────────────────────────────────────────────────────
// LuniferStopAlarmIntent
// ─────────────────────────────────────────────────────────────
// The App Intent AlarmKit runs when the user stops the main Lunifer
// alarm. Crucially, the system invokes this no matter WHERE the user
// taps Stop — the lock screen, the Dynamic Island, or the in-app
// alert — and launches the app in the background to run it if needed.
//
// That makes it the reliable hook for self-perpetuation: whichever way
// the alarm gets dismissed, this schedules the next wake day. It's
// attached to the main alarm in LuniferAlarm.scheduleAlarm(...) via
// AlarmConfiguration(stopIntent:). (Added alarms are not given this
// intent — they keep their own in-app repeat/delete handling.)
//
// LiveActivityIntent is the protocol AlarmKit requires for stop /
// secondary intents (AlarmManager.AlarmConfiguration.stopIntent is
// typed `any LiveActivityIntent`).

struct LuniferStopAlarmIntent: LiveActivityIntent {

    static var title: LocalizedStringResource = "Stop Lunifer Alarm"

    /// The AlarmKit alarm ID this intent was scheduled for. AlarmKit persists
    /// the intent (encoding its parameters) and restores it when the alarm is
    /// stopped, so this value survives even a cold background relaunch. We don't
    /// currently branch on it — the main alarm is a singleton and the reschedule
    /// targets the next wake day regardless — but it's kept for traceability and
    /// future per-alarm handling.
    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        await LuniferAlarm.shared.rescheduleAfterSystemStop()
        return .result()
    }
}
