#if DEBUG
import Foundation
import SwiftUI
import UserNotifications

enum UITestSupport {
    static var dashboardEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-dashboard")
    }

    static var alarmPermissionDenied: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-denied-alarm")
    }

    static var wakeReminderPause: (() async -> Void)?
    static var wakeReminderAfterAdd: (() async -> Void)?

    static var didRejectSchedule = false
    static var forceScheduleFailure = false
    static var forceAlarmRegistryReadFailure = false
    static var alarmRefreshDelayNanoseconds: UInt64 = 0

    static func rejectScheduleIfRequested() throws {
        guard forceScheduleFailure || ProcessInfo.processInfo.arguments.contains("--ui-test-fail-scheduling") else { return }
        didRejectSchedule = true
        throw NSError(domain: "LuniferUITest", code: 1)
    }

    static func rejectAlarmRegistryReadIfRequested() throws {
        guard forceAlarmRegistryReadFailure else { return }
        throw NSError(domain: "LuniferUITest", code: 2)
    }

    static func pauseAlarmRefreshIfRequested() async {
        guard alarmRefreshDelayNanoseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: alarmRefreshDelayNanoseconds)
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
        if ProcessInfo.processInfo.arguments.contains("--ui-test-rest-day") {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            let ids = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
            answers.wakeDays.removeAll { $0 == ids[Calendar.current.component(.weekday, from: tomorrow) - 1] }
        }
        defaults.removeObject(forKey: AppPreferencesStore.Keys.commuteMessageAlarmTimestamps)
        if ProcessInfo.processInfo.arguments.contains("--ui-test-expired-commute-message") {
            defaults.set([Date().addingTimeInterval(-3 * 3600 - 60).timeIntervalSince1970], forKey: AppPreferencesStore.Keys.commuteMessageAlarmTimestamps)
        }
        answers.saveToDefaults()
        return answers
    }
}

/// Exercises the real notification center and dashboard off switch with deterministic timing.
struct WakeReminderRaceProbe: View {
    @State private var paused = false
    @State private var phase = "idle"
    @State private var pending = 0

    var body: some View {
        VStack {
            Text("\(phase); pending=\(pending)")
                .accessibilityIdentifier("wakeReminder.probe")
            Button("Start reminder race") {
                Task { @MainActor in
                    let center = UNUserNotificationCenter.current()
                    _ = try? await center.requestAuthorization(options: [.alert, .sound, .provisional])
                    let date = Date().addingTimeInterval(36 * 3600)
                    if UserDefaults.standard.bool(forKey: "luniferEnabled") {
                        guard await LuniferAlarm.shared.scheduleAlarm(for: date) else {
                            phase = "alarm failed"
                            return
                        }
                    }
                    if ProcessInfo.processInfo.arguments.contains("--ui-test-all-notifications") {
                        for id in ["lunifer.commute.leave.reminder", "lunifer.commute.delta.alert", "lunifer.calendar.nudge", "lunifer.restday.event.prompt"] {
                            let content = UNMutableNotificationContent()
                            content.title = "Pending alert"
                            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)))
                        }
                    }
                    WakeNotification.shared.cancel()
                    UITestSupport.wakeReminderPause = {
                        paused = true
                        phase = "paused"
                        while paused { try? await Task.sleep(for: .milliseconds(20)) }
                    }
                    await WakeNotification.shared.schedule(wakeDate: date, answers: SurveyAnswers())
                    UITestSupport.wakeReminderPause = nil
                    pending = await center.pendingNotificationRequests().filter { ProcessInfo.processInfo.arguments.contains("--ui-test-all-notifications") ? $0.identifier != "lunifer.reengagement" : $0.identifier == "lunifer.wake.reminder" }.count
                    phase = "finished"
                }
            }.accessibilityIdentifier("wakeReminder.start")
            Button("Resume reminder") { paused = false }
                .accessibilityIdentifier("wakeReminder.resume")
        }
        .font(.caption)
        .padding()
        .background(.black)
        .task {
            while !Task.isCancelled {
                pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
                    .filter { ProcessInfo.processInfo.arguments.contains("--ui-test-all-notifications") ? $0.identifier != "lunifer.reengagement" : $0.identifier == "lunifer.wake.reminder" }.count
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
#endif
