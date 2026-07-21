import Foundation
import AppIntents


struct LuniferStopAlarmIntent: LiveActivityIntent {

    static var title: LocalizedStringResource = "Stop Lunifer Alarm"

    

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
