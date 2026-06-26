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
// AlarmConfiguration(stopIntent:).
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

// ─────────────────────────────────────────────────────────────
// LuniferAddedAlarmStopIntent
// ─────────────────────────────────────────────────────────────
// The App Intent AlarmKit runs when the user stops a user-added alarm
// from outside the app (lock screen, Dynamic Island). Carries the
// logical AddedAlarm.id so the engine can run the same one-shot delete
// or repeating-reschedule logic that the in-app Stop button runs via
// stopAlarm(). Without this, added alarms dismissed from the system UI
// leave zombie dashboard cards and repeating alarms never advance.

struct LuniferAddedAlarmStopIntent: LiveActivityIntent {

    static var title: LocalizedStringResource = "Stop Lunifer Added Alarm"

    /// The logical AddedAlarm.id (not the AlarmKit UUID) for this alarm.
    /// AlarmKit persists and restores this across background relaunches,
    /// so the correct alarm is always cleaned up regardless of how it
    /// was stopped.
    @Parameter(title: "Logical Alarm ID")
    var logicalAlarmID: String

    init() {}

    init(logicalAlarmID: String) {
        self.logicalAlarmID = logicalAlarmID
    }

    func perform() async throws -> some IntentResult {
        guard let logicalID = UUID(uuidString: logicalAlarmID) else { return .result() }
        await LuniferAlarm.shared.handleAddedAlarmSystemStop(logicalID: logicalID)
        return .result()
    }
}
