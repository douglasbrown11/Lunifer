import XCTest
@testable import Lunifer

@MainActor
final class WakeTrackingTests: XCTestCase {
    private let defaults = UserDefaults.standard
    private let keys = [
        "luniferEnabled", "lunifer_sleep_history", "lunifer_wake_time_samples",
        "lunifer_morning_wake_recorded_day", "lunifer_avg_sleep_onset_weekday",
        "lunifer_avg_sleep_onset_weekend", "lunifer_avg_sleep_onset",
        "lunifer_last_retroactive_run", "lunifer_last_retroactive_analysis",
        "lunifer_last_interaction", "lunifer_interaction_log", "lunifer_sleep_log",
        "surveyAnswers"
    ]
    private var saved: [String: Any] = [:]
    private var alarm: Date?
    private var wasStopped = false

    override func setUp() async throws {
        for key in keys {
            saved[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
        alarm = LuniferAlarm.shared.scheduledWakeTime
        LuniferAlarm.shared.scheduledWakeTime = nil
        wasStopped = BackgroundActivitySession.shared.isStopped
        BackgroundActivitySession.shared.resume()
        defaults.set(false, forKey: "luniferEnabled")
    }

    override func tearDown() async throws {
        for key in keys {
            if let value = saved[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        LuniferAlarm.shared.scheduledWakeTime = alarm
        if wasStopped { BackgroundActivitySession.shared.stop() }
        else { BackgroundActivitySession.shared.resume() }
    }

    private var returned: Date {
        Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
    }

    func testReturningHoursLaterWhileDisabledPreservesDetectedWake() async {
        let wake = returned.addingTimeInterval(-3 * 3600)
        let onset = wake.addingTimeInterval(-8 * 3600)
        SleepHistoryStore.shared.recordNight(date: wake, duration: 8, onset: onset, wake: wake)
        for enabled in [false, true] {
            defaults.set(enabled, forKey: "luniferEnabled")
            // A fresh tracker represents an app relaunch with restored history.
            let tracker = SleepTracker()
            await tracker.confirmWakeFromMorningPickup(now: returned)
            XCTAssertEqual(tracker.estimatedWakeTime, wake)
            XCTAssertEqual(SleepHistoryStore.shared.allHistory().first?.wakeTime, wake)
            XCTAssertEqual(SleepHistoryStore.shared.allHistory().first?.durationHours, 8)
            XCTAssertFalse(SleepHistoryStore.shared.wakeTimeSamples(since: wake, through: returned).contains(returned))
        }
    }

    func testWakeOnlySampleSurvivesLaterReturnAndReenablement() async {
        let wake = returned.addingTimeInterval(-3 * 3600)
        SleepHistoryStore.shared.recordWakeTimeSample(wake)
        for enabled in [false, true] {
            defaults.set(enabled, forKey: "luniferEnabled")
            await SleepTracker().confirmWakeFromMorningPickup(now: returned)
            XCTAssertEqual(SleepHistoryStore.shared.wakeTimeSamples(since: wake, through: returned), [wake])
            if let completed = SleepHistoryStore.shared.allHistory().first {
                XCTAssertEqual(completed.wakeTime, wake)
            }
        }
    }

    func testFreshHistoryStillRecordsMorningWakeWhileDisabled() async {
        await SleepTracker().confirmWakeFromMorningPickup(now: returned)
        XCTAssertEqual(SleepHistoryStore.shared.wakeTimeSamples(
            since: Calendar.current.startOfDay(for: returned), through: returned
        ), [returned])
    }

    func testTrackingStartsAndRecordsInteractionsWhileDisabled() async {
        // Avoid querying unavailable simulator motion history in this lifecycle test.
        SleepTrackingStore.shared.setLastRetroactiveRunDate(Date())
        let tracker = SleepTracker()
        await tracker.startTracking()
        XCTAssertTrue(tracker.isTracking)
        XCTAssertNotNil(SleepTrackingStore.shared.lastInteractionDate())
        tracker.stopTracking()
        XCTAssertFalse(tracker.isTracking)
        XCTAssertNil(tracker.estimatedWakeTime)
        XCTAssertNil(tracker.estimatedSleepOnset)
    }

    func testSignOutPreventsWakeRecordingAndNextSessionStartsClean() async {
        let tracker = SleepTracker()
        BackgroundActivitySession.shared.stop()
        await tracker.confirmWakeFromMorningPickup(now: returned)
        XCTAssertTrue(SleepHistoryStore.shared.wakeTimeSamples(since: .distantPast, through: returned).isEmpty)
        await tracker.startTracking()
        XCTAssertFalse(tracker.isTracking)
        tracker.stopTracking()
        SleepTrackingStore.shared.clearLocalData()
        SleepHistoryStore.shared.clearLocalData()
        BackgroundActivitySession.shared.resume()
        await tracker.confirmWakeFromMorningPickup(now: returned)
        XCTAssertEqual(SleepHistoryStore.shared.wakeTimeSamples(since: .distantPast, through: returned), [returned])
    }
}
