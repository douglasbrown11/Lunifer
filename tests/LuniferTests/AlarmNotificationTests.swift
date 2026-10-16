import XCTest
import UserNotifications
import AlarmKit
@testable import Lunifer

@MainActor
final class AlarmNotificationTests: XCTestCase {
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let identifier = "lunifer.wake.reminder"
    private let keys = ["luniferEnabled", "wakeReminderEnabled", "batteryAlertEnabled", "allNotificationsEnabled", "addedAlarms"]
    private var saved: [String: Any] = [:]

    override func setUp() async throws {
        for key in keys {
            saved[key] = defaults.object(forKey: key)
            defaults.set(true, forKey: key)
        }
        BackgroundActivitySession.shared.resume()
        WakeNotification.shared.cancel()
        let authorized = try await center.requestAuthorization(options: [.alert, .sound, .provisional])
        XCTAssertTrue(authorized)
    }

    override func tearDown() async throws {
        UITestSupport.wakeReminderPause = nil
        UITestSupport.wakeReminderAfterAdd = nil
        WakeNotification.shared.cancel()
        BatteryAlarmNotification.shared.cancelWarning()
        for key in keys {
            if let value = saved[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
    }

    private func scheduleWake() async {
        await WakeNotification.shared.schedule(wakeDate: Date().addingTimeInterval(36 * 3600), answers: SurveyAnswers())
    }

    private func pendingCount() async -> Int {
        await center.pendingNotificationRequests().filter { $0.identifier == identifier }.count
    }

    func testAddedAlarmIsSilencedAndCannotBeRecreatedWhileOff() async throws {
        let alarm = LuniferAlarm.shared
        await alarm.requestAuthorization()
        XCTAssertTrue(alarm.isAuthorized)
        let id = UUID()
        let date = Date().addingTimeInterval(7200)
        let records: [[String: Any]] = [["id": id.uuidString, "timestamp": date.timeIntervalSince1970, "label": "Test", "snoozeMinutes": 5, "sound": "", "repeatDays": []]]
        defaults.set(try JSONSerialization.data(withJSONObject: records), forKey: "addedAlarms")
        await alarm.cancelAlarm()
        await alarm.scheduleAddedAlarm(for: date, alarmID: id, snoozeMinutes: 5)
        let before = try AlarmManager.shared.alarms
        XCTAssertTrue(before.contains { $0.schedule == .fixed(date) })
        defaults.set(false, forKey: "luniferEnabled")
        await alarm.cancelAllAddedAlarms()
        await alarm.scheduleAddedAlarm(for: date, alarmID: id, snoozeMinutes: 5)
        let after = try AlarmManager.shared.alarms
        XCTAssertFalse(after.contains { $0.schedule == .fixed(date) })
        defaults.set(true, forKey: "luniferEnabled")
        await alarm.reconcileAddedAlarms()
        let restored = try AlarmManager.shared.alarms
        XCTAssertTrue(restored.contains { $0.schedule == .fixed(date) })
        await alarm.cancelAllAddedAlarms()
    }

    func testOffCancelsEveryOrdinaryAlertButPreservesSevenDayReminder() async throws {
        let ids = ["lunifer.wake.reminder", "lunifer.battery.warning", "lunifer.commute.leave.reminder", "lunifer.commute.delta.alert", "lunifer.calendar.nudge", "lunifer.restday.event.prompt"]
        for id in ids {
            try await center.add(UNNotificationRequest(identifier: id, content: UNMutableNotificationContent(), trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)))
        }
        defaults.set(false, forKey: "luniferEnabled")
        await TurnBackOnNotification.shared.schedule()
        AlarmNotificationScheduler.cancelOrdinaryNotifications()
        let pending = await center.pendingNotificationRequests()
        XCTAssertFalse(pending.contains { ids.contains($0.identifier) })
        let reminder = try XCTUnwrap(pending.first { $0.identifier == "lunifer.reengagement" })
        XCTAssertEqual((reminder.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 7 * 24 * 3600)
        TurnBackOnNotification.shared.cancel()
    }

    func testCommuteCannotRescheduleWhileOffAndRecoversWhenEnabled() async {
        let savedPreference = defaults.object(forKey: "commuteReminderEnabled")
        defaults.set(true, forKey: "commuteReminderEnabled")
        defer {
            if let savedPreference { defaults.set(savedPreference, forKey: "commuteReminderEnabled") }
            else { defaults.removeObject(forKey: "commuteReminderEnabled") }
            CommuteNotification.shared.cancelAll()
        }
        defaults.set(false, forKey: "luniferEnabled")
        CommuteNotification.shared.scheduleLeaveReminder(leaveTime: Date().addingTimeInterval(7200))
        CommuteNotification.shared.scheduleDeltaAlert(newLeaveTime: Date().addingTimeInterval(7200), didIncrease: true)
        let blocked = await center.pendingNotificationRequests()
        XCTAssertFalse(blocked.contains { $0.identifier.hasPrefix("lunifer.commute") })
        defaults.set(true, forKey: "luniferEnabled")
        CommuteNotification.shared.scheduleLeaveReminder(leaveTime: Date().addingTimeInterval(7200))
        var restored = false
        for _ in 0..<50 {
            restored = await center.pendingNotificationRequests().contains { $0.identifier == "lunifer.commute.leave.reminder" }
            if restored { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(restored)
    }

    func testSchedulingWhileOffClearsStaleReminder() async {
        await scheduleWake()
        let before = await pendingCount()
        XCTAssertEqual(before, 1)
        defaults.set(false, forKey: "luniferEnabled")
        await scheduleWake()
        let after = await pendingCount()
        XCTAssertEqual(after, 0)
    }

    func testDisableDuringPermissionReadPreventsSubmission() async {
        UITestSupport.wakeReminderPause = {
            self.defaults.set(false, forKey: "luniferEnabled")
            WakeNotification.shared.cancel()
        }
        await scheduleWake()
        let count = await pendingCount()
        XCTAssertEqual(count, 0)
    }

    func testDisableDuringSubmissionRemovesAcceptedReminder() async {
        UITestSupport.wakeReminderAfterAdd = {
            let accepted = await self.pendingCount()
            XCTAssertEqual(accepted, 1)
            self.defaults.set(false, forKey: "luniferEnabled")
            WakeNotification.shared.cancel()
        }
        await scheduleWake()
        let count = await pendingCount()
        XCTAssertEqual(count, 0)
    }

    func testCancellationStillInvalidatesWorkAfterReenabling() async {
        UITestSupport.wakeReminderPause = {
            self.defaults.set(false, forKey: "luniferEnabled")
            WakeNotification.shared.cancel()
            self.defaults.set(true, forKey: "luniferEnabled")
        }
        await scheduleWake()
        let stale = await pendingCount()
        XCTAssertEqual(stale, 0)
        UITestSupport.wakeReminderPause = nil
        await scheduleWake()
        let fresh = await pendingCount()
        XCTAssertEqual(fresh, 1)
    }

    func testOldSubmissionCleanupPreservesQueuedReplacement() async {
        var replacement: Task<Void, Never>?
        UITestSupport.wakeReminderAfterAdd = {
            UITestSupport.wakeReminderAfterAdd = nil
            self.defaults.set(false, forKey: "luniferEnabled")
            WakeNotification.shared.cancel()
            self.defaults.set(true, forKey: "luniferEnabled")
            replacement = Task { @MainActor in await self.scheduleWake() }
            await Task.yield()
        }
        await scheduleWake()
        await replacement?.value
        let count = await pendingCount()
        XCTAssertEqual(count, 1)
    }

    func testNotificationPreferencesPreventRescheduling() async {
        for key in ["wakeReminderEnabled", "allNotificationsEnabled"] {
            defaults.set(false, forKey: key)
            await scheduleWake()
            let count = await pendingCount()
            XCTAssertEqual(count, 0)
            defaults.set(true, forKey: key)
        }
    }

    func testBatteryNotificationSubmissionIsBlockedWhileOff() async {
        let scheduler = AlarmNotificationScheduler(identifier: "lunifer.battery.warning", preferenceKey: "batteryAlertEnabled")
        defaults.set(false, forKey: "luniferEnabled")
        await scheduler.schedule(content: UNMutableNotificationContent(), trigger: nil)
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        XCTAssertFalse(pending.contains { $0.identifier == "lunifer.battery.warning" })
        XCTAssertFalse(delivered.contains { $0.request.identifier == "lunifer.battery.warning" })
    }

    func testSignOutAndAccountSwitchInvalidateSuspendedReminder() async {
        UITestSupport.wakeReminderPause = {
            BackgroundActivitySession.shared.stop()
            BackgroundActivitySession.shared.resume()
        }
        await scheduleWake()
        let count = await pendingCount()
        XCTAssertEqual(count, 0)
    }

    func testFreshInstallPreferenceDefaultsAllowScheduling() async {
        for key in keys { defaults.removeObject(forKey: key) }
        await scheduleWake()
        let count = await pendingCount()
        XCTAssertEqual(count, 1)
    }

    func testRestoredOffStateClearsStaleNotificationWithNewScheduler() async {
        await scheduleWake()
        let before = await pendingCount()
        XCTAssertEqual(before, 1)
        defaults.set(false, forKey: "luniferEnabled")
        let restoredScheduler = AlarmNotificationScheduler(identifier: identifier, preferenceKey: "wakeReminderEnabled")
        await restoredScheduler.schedule(content: UNMutableNotificationContent(), trigger: nil)
        let after = await pendingCount()
        XCTAssertEqual(after, 0)
    }

    func testCancelRemovesDeliveredReminder() async throws {
        let content = UNMutableNotificationContent()
        content.title = "Reminder cancellation test"
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        var delivered = false
        for _ in 0..<50 {
            delivered = await center.deliveredNotifications().contains { $0.request.identifier == identifier }
            if delivered { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(delivered, "The test must first observe an actual delivered notification.")
        WakeNotification.shared.cancel()
        let remaining = await center.deliveredNotifications()
        XCTAssertFalse(remaining.contains { $0.request.identifier == identifier })
    }
}
