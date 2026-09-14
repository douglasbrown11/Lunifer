#if DEBUG
import Foundation

enum UITestSupport {
    static var dashboardEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-dashboard")
    }

    static var alarmPermissionDenied: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-denied-alarm")
    }

    static var didRejectSchedule = false

    static func rejectScheduleIfRequested() throws {
        guard ProcessInfo.processInfo.arguments.contains("--ui-test-fail-scheduling") else { return }
        didRejectSchedule = true
        throw NSError(domain: "LuniferUITest", code: 1)
    }

    static func dashboardAnswers() -> SurveyAnswers? {
        guard dashboardEnabled else { return nil }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppPreferencesStore.Keys.luniferEnabled)
        defaults.set(false, forKey: AppPreferencesStore.Keys.overrideActive)
        defaults.set(true, forKey: AppPreferencesStore.Keys.hasSeenWalkthrough)
        defaults.removeObject(forKey: AppPreferencesStore.Keys.overrideTimestamp)
        defaults.removeObject(forKey: AppPreferencesStore.Keys.addedAlarms)
        AppPreferencesStore.shared.clearRestDayAlarmOptIn()
        var answers = SurveyAnswers()
        answers.calendar = "none"
        answers.wakeDays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        answers.saveToDefaults()
        return answers
    }
}
#endif
