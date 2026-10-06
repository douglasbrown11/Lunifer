//
//  LuniferTests.swift
//  LuniferTests
//
//  Created by Douglas Brown on 3/11/26.
//

import XCTest
@testable import Lunifer

@MainActor
final class LuniferTests: XCTestCase {
    private let defaults = UserDefaults.standard
    private var savedDefaults: [String: Any] = [:]
    private let keys = [
        "luniferEnabled",
        "overrideActive",
        "surveyAnswers",
        "lunifer_sleep_history",
        "restDayAlarmOptInDate",
        AppPreferencesStore.Keys.disabledPendingAlarmTimestamp,
        AppPreferencesStore.Keys.pendingReplacementAlarmTimestamp,
        AppPreferencesStore.Keys.pendingStopRescheduleTimestamp,
        AppPreferencesStore.Keys.finalizedMainAlarmTimestamp
    ]

    override func setUp() async throws {
        for key in keys {
            savedDefaults[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: "luniferEnabled")
        LuniferAlarm.shared.scheduledWakeTime = nil
        LuniferAlarm.shared.activeAlarms = []
        CommuteManager.shared.currentDurationMinutes = 0
        CommuteManager.shared.ignoredCommuteMinutes = nil
        UITestSupport.forceScheduleFailure = false
        UITestSupport.forceAlarmRegistryReadFailure = false
        UITestSupport.alarmRefreshDelayNanoseconds = 0
    }

    override func tearDown() async throws {
        for key in keys {
            if let value = savedDefaults[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        LuniferAlarm.shared.scheduledWakeTime = nil
        LuniferAlarm.shared.activeAlarms = []
        CommuteManager.shared.currentDurationMinutes = 0
        CommuteManager.shared.ignoredCommuteMinutes = nil
        UITestSupport.forceScheduleFailure = false
        UITestSupport.forceAlarmRegistryReadFailure = false
        UITestSupport.alarmRefreshDelayNanoseconds = 0
    }

    func testSleepBasedWakeTimeMatchesTargetDayAcrossRestDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
        }
        let monday = date(5, 0)
        XCTAssertNil(LuniferAlarm.sleepBasedWakeTime(
            onset: date(1, 23), sleepHours: 8, targetDay: monday, calendar: calendar
        ))
        XCTAssertEqual(LuniferAlarm.sleepBasedWakeTime(
            onset: date(4, 23), sleepHours: 8, targetDay: monday, calendar: calendar
        ), date(5, 7))
        XCTAssertEqual(LuniferAlarm.sleepBasedWakeTime(
            onset: date(5, 1), sleepHours: 8, targetDay: monday, calendar: calendar
        ), date(5, 9))
        XCTAssertNil(LuniferAlarm.sleepBasedWakeTime(
            onset: nil, sleepHours: 8, targetDay: monday, calendar: calendar
        ))
    }

    func testWakeHistoryMedianResistsOutliersAndHandlesEvenCounts() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2))!
        func loadWakeHours(_ hours: [Int]) {
            let entries = hours.enumerated().map { index, hour in
                let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7 + index * 7, hour: hour))!
                return ["wake": date.timeIntervalSince1970]
            }
            defaults.set(entries, forKey: "lunifer_sleep_history")
        }
        loadWakeHours([10, 7, 7])
        XCTAssertEqual(SleepHistoryStore.shared.medianWakeTime(forWeekday: 2, now: now)?.hour, 7)
        loadWakeHours([10, 8, 7, 7])
        let evenMedian = SleepHistoryStore.shared.medianWakeTime(forWeekday: 2, now: now)
        XCTAssertEqual(evenMedian?.hour, 7)
        XCTAssertEqual(evenMedian?.minute, 30)
        XCTAssertNil(SleepHistoryStore.shared.medianWakeTime(forWeekday: 3, now: now))
        loadWakeHours([7])
        XCTAssertNil(SleepHistoryStore.shared.medianWakeTime(forWeekday: 2, now: now))
    }

    func testWakeHistoryMedianUsesOnlyLastTenWeeks() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 7))!
        let cutoff = calendar.date(byAdding: .weekOfYear, value: -10, to: now)!
        let recent = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
        let future = calendar.date(byAdding: .weekOfYear, value: 1, to: now)!
        func load(_ dates: [Date]) {
            defaults.set(dates.map { ["wake": $0.timeIntervalSince1970] }, forKey: "lunifer_sleep_history")
        }
        load([cutoff, recent, cutoff.addingTimeInterval(-60), future])
        let median = SleepHistoryStore.shared.medianWakeTime(forWeekday: 2, now: now)
        XCTAssertEqual(median?.hour, 7)
        XCTAssertEqual(median?.minute, 0)
        load([recent, cutoff.addingTimeInterval(-60), future])
        XCTAssertNil(SleepHistoryStore.shared.medianWakeTime(forWeekday: 2, now: now))
    }

    func testConfiguredCommuteAndRoutineApplyWhenCommuteIsConfigured() {
        var answers = SurveyAnswers()
        answers.commuteMode = "walk"
        answers.commute = TimeValue(hours: 0, minutes: 20, auto: false)
        answers.routine = TimeValue(hours: 0, minutes: 45, auto: false)
        XCTAssertEqual(CommuteManager.surveyDuration(from: answers), 20)
        XCTAssertEqual(LuniferAlarm.shared.routineCommuteBufferSeconds(answers: answers), 65 * 60)
    }

    func testMissingCommuteModeDisablesTravelBuffer() {
        var answers = SurveyAnswers()
        answers.commuteMode = ""
        answers.routine = TimeValue(hours: 0, minutes: 0, auto: false)
        XCTAssertEqual(CommuteManager.surveyDuration(from: answers), 0)
        XCTAssertEqual(LuniferAlarm.shared.routineCommuteBufferSeconds(answers: answers), 0)
    }

    func testAutoCommuteFallsBackToZeroUntilLiveRouteExists() {
        var answers = SurveyAnswers()
        answers.commuteMode = "drive"
        answers.commute = TimeValue(hours: 0, minutes: 30, auto: true)
        answers.routine = TimeValue(hours: 0, minutes: 45, auto: false)
        CommuteManager.shared.currentDurationMinutes = 0

        XCTAssertEqual(CommuteManager.surveyDuration(from: answers), 0)
        XCTAssertEqual(LuniferAlarm.shared.routineCommuteBufferSeconds(answers: answers), 45 * 60)

        CommuteManager.shared.currentDurationMinutes = 18
        XCTAssertEqual(LuniferAlarm.shared.routineCommuteBufferSeconds(answers: answers), 63 * 60)
    }

    func testAbsurdCommuteIsIgnoredForAlarmMathAndFlagged() {
        var answers = SurveyAnswers()
        answers.commuteMode = "drive"
        answers.commute = TimeValue(hours: 0, minutes: 30, auto: true)
        answers.routine = TimeValue(hours: 0, minutes: 45, auto: false)

        CommuteManager.shared.currentDurationMinutes = 360

        XCTAssertEqual(LuniferAlarm.shared.routineCommuteBufferSeconds(answers: answers), 45 * 60)
        XCTAssertEqual(CommuteManager.shared.currentDurationMinutes, 0)
        XCTAssertEqual(CommuteManager.shared.ignoredCommuteMinutes, 360)
    }

    func testThreeHourCommuteIsAllowedForAlarmMath() {
        var answers = SurveyAnswers()
        answers.commuteMode = "drive"
        answers.commute = TimeValue(hours: 0, minutes: 30, auto: true)
        answers.routine = TimeValue(hours: 0, minutes: 45, auto: false)

        CommuteManager.shared.currentDurationMinutes = 180

        XCTAssertEqual(LuniferAlarm.shared.routineCommuteBufferSeconds(answers: answers), 225 * 60)
        XCTAssertNil(CommuteManager.shared.ignoredCommuteMinutes)
    }

    func testHardFallbackSubtractsRoutineButNotCommute() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let targetDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))!

        var answers = SurveyAnswers()
        answers.calendar = "none"
        answers.routine = TimeValue(hours: 0, minutes: 45, auto: false)
        answers.commuteMode = "drive"
        answers.commute = TimeValue(hours: 0, minutes: 30, auto: false)

        let resolution = await LuniferAlarm.shared.resolveBaselineAlarmDate(answers: answers, targetDay: targetDay)

        XCTAssertEqual(resolution.alarmDate, calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 7, minute: 15)))
        XCTAssertEqual(resolution.routineMinutes, 45)
        XCTAssertEqual(resolution.commuteMinutes, 0)
        XCTAssertNil(resolution.firstEvent)
    }

    func testWakeReminderRequiresConfirmedAuthorizedAlarm() {
        let confirmed = Date().addingTimeInterval(3600)

        XCTAssertFalse(LuniferMain.shouldScheduleWakeReminder(
            luniferEnabled: true,
            alarmAuthorized: false,
            confirmedAlarmDate: confirmed
        ))
        XCTAssertFalse(LuniferMain.shouldScheduleWakeReminder(
            luniferEnabled: true,
            alarmAuthorized: true,
            confirmedAlarmDate: nil
        ))
        XCTAssertFalse(LuniferMain.shouldScheduleWakeReminder(
            luniferEnabled: false,
            alarmAuthorized: true,
            confirmedAlarmDate: confirmed
        ))
        XCTAssertTrue(LuniferMain.shouldScheduleWakeReminder(
            luniferEnabled: true,
            alarmAuthorized: true,
            confirmedAlarmDate: confirmed
        ))
    }

    func testFinalizedMainAlarmAppliesOnlyToSameFutureWakeDay() throws {
        let calendar = Calendar.current
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())))
        let tomorrowAlarm = try XCTUnwrap(calendar.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow))
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: tomorrow))
        let nextDayAlarm = try XCTUnwrap(calendar.date(bySettingHour: 7, minute: 0, second: 0, of: nextDay))

        AppPreferencesStore.shared.finalizedMainAlarmDate = tomorrowAlarm

        XCTAssertTrue(AppPreferencesStore.shared.isMainAlarmFinalized(for: tomorrowAlarm, calendar: calendar))
        XCTAssertFalse(AppPreferencesStore.shared.isMainAlarmFinalized(for: nextDayAlarm, calendar: calendar))

        AppPreferencesStore.shared.finalizedMainAlarmDate = Date().addingTimeInterval(-60)

        XCTAssertNil(AppPreferencesStore.shared.finalizedMainAlarmDate)
    }

    func testGoogleCanceledStatusIsExcludedFromAlarmSelection() {
        XCTAssertTrue(GoogleCalendarService.isCanceled("cancelled"))
        XCTAssertTrue(GoogleCalendarService.isCanceled("CANCELLED"))
        XCTAssertFalse(GoogleCalendarService.isCanceled("confirmed"))
        XCTAssertFalse(GoogleCalendarService.isCanceled(nil))
    }

    func testStaleAlarmDatesAreNotSchedulable() {
        let now = Date()

        XCTAssertFalse(LuniferAlarm.shared.isSchedulableAlarmDate(now.addingTimeInterval(-1), now: now))
        XCTAssertFalse(LuniferAlarm.shared.isSchedulableAlarmDate(now.addingTimeInterval(30), now: now))
        XCTAssertTrue(LuniferAlarm.shared.isSchedulableAlarmDate(now.addingTimeInterval(60), now: now))
    }

    func testDisabledPendingAlarmMemoryExpiresAfterAlarmTime() {
        let futureAlarm = Date().addingTimeInterval(3600)
        AppPreferencesStore.shared.disabledPendingAlarmDate = futureAlarm

        XCTAssertEqual(
            AppPreferencesStore.shared.disabledPendingAlarmDate?.timeIntervalSince1970.rounded(),
            futureAlarm.timeIntervalSince1970.rounded()
        )

        AppPreferencesStore.shared.disabledPendingAlarmDate = Date().addingTimeInterval(-60)

        XCTAssertNil(AppPreferencesStore.shared.disabledPendingAlarmDate)
    }

    func testFailedRegistryReadMarksAlarmStateUncertain() {
        UITestSupport.forceAlarmRegistryReadFailure = true

        XCTAssertFalse(LuniferAlarm.shared.hasPendingMainAlarm())
        XCTAssertTrue(LuniferAlarm.shared.alarmRegistryUncertain)
    }

    func testPendingReplacementAlarmIsPreferredDuringCrashRecovery() {
        let now = Date()
        let oldAlarm = now.addingTimeInterval(3600)
        let recoveredReplacement = now.addingTimeInterval(7200)

        let chosen = LuniferAlarm.preferredMainAlarmDate(
            from: [oldAlarm, recoveredReplacement],
            pendingReplacement: recoveredReplacement,
            now: now
        )

        XCTAssertEqual(chosen, recoveredReplacement)
    }

    func testEarliestAlarmIsUsedWithoutPendingReplacementMarker() {
        let now = Date()
        let first = now.addingTimeInterval(3600)
        let second = now.addingTimeInterval(7200)

        let chosen = LuniferAlarm.preferredMainAlarmDate(
            from: [second, first],
            pendingReplacement: nil,
            now: now
        )

        XCTAssertEqual(chosen, first)
    }

    func testOldAlarmMetadataDefaultsToMainIdentity() throws {
        let wakeDate = Date()
        let oldMetadataJSON = """
        {
          "scheduledWakeTime": \(wakeDate.timeIntervalSince1970),
          "calendarEventTitle": "your first event",
          "routineMinutes": 60,
          "commuteMinutes": 30
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let metadata = try decoder.decode(LuniferAlarmMetadata.self, from: oldMetadataJSON)

        XCTAssertEqual(metadata.alarmKind, LuniferAlarmMetadataKind.main)
        XCTAssertNil(metadata.addedAlarmID)
    }

    func testAddedAlarmMetadataCarriesLogicalIdentity() throws {
        let logicalID = UUID()
        let metadata = LuniferAlarmMetadata(
            scheduledWakeTime: Date(),
            calendarEventTitle: "",
            routineMinutes: 0,
            commuteMinutes: 0,
            alarmKind: LuniferAlarmMetadataKind.added,
            addedAlarmID: logicalID
        )

        XCTAssertEqual(metadata.alarmKind, LuniferAlarmMetadataKind.added)
        XCTAssertEqual(metadata.addedAlarmID, logicalID)
    }

    func testRefreshStopsWhenLuniferIsDisabledMidCalculation() async throws {
        var answers = SurveyAnswers()
        answers.wakeDays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        UITestSupport.alarmRefreshDelayNanoseconds = 50_000_000

        let refresh = Task { @MainActor in
            await LuniferAlarm.shared.refreshTomorrowAlarm(answers: answers)
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        defaults.set(false, forKey: AppPreferencesStore.Keys.luniferEnabled)

        let refreshed = await refresh.value

        XCTAssertNil(refreshed)
        XCTAssertNil(LuniferAlarm.shared.scheduledWakeTime)
    }

    func testAlarmInputTimeoutUsesFallback() async {
        let value = await LuniferAlarm.withAlarmInputTimeout(
            nanoseconds: 1_000_000,
            fallback: 42
        ) {
            try? await Task.sleep(nanoseconds: 50_000_000)
            return 7
        }

        XCTAssertEqual(value, 42)
    }

    private func upcomingAlarmToday() throws -> Date {
        let now = Date()
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)))
        return now.addingTimeInterval(min(3600, tomorrow.timeIntervalSince(now) / 2))
    }

    func testDashboardRefreshPreservesTodaysAlarmWhenTomorrowIsRestDay() async throws {
        var answers = SurveyAnswers()
        answers.wakeDays = []
        let morningAlarm = try upcomingAlarmToday()
        LuniferAlarm.shared.scheduledWakeTime = morningAlarm

        let displayedAlarm = await LuniferAlarm.shared.refreshTomorrowAlarm(answers: answers)

        XCTAssertEqual(displayedAlarm, morningAlarm)
        XCTAssertEqual(LuniferAlarm.shared.scheduledWakeTime, morningAlarm)
    }

    func testForegroundAdaptiveCheckPreservesTodaysAlarmWhenTomorrowIsRestDay() async throws {
        var answers = SurveyAnswers()
        answers.wakeDays = []
        answers.saveToDefaults()
        let morningAlarm = try upcomingAlarmToday()
        LuniferAlarm.shared.scheduledWakeTime = morningAlarm

        await LuniferAlarm.shared.checkAlarmAgainstCalendar()

        XCTAssertEqual(LuniferAlarm.shared.scheduledWakeTime, morningAlarm)
    }

    func testDashboardRefreshPreservesTodaysAlarmWhenTomorrowIsWakeDay() async throws {
        var answers = SurveyAnswers()
        answers.wakeDays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        let morningAlarm = try upcomingAlarmToday()
        LuniferAlarm.shared.scheduledWakeTime = morningAlarm

        let displayedAlarm = await LuniferAlarm.shared.refreshTomorrowAlarm(answers: answers)

        XCTAssertEqual(displayedAlarm, morningAlarm)
        XCTAssertEqual(LuniferAlarm.shared.scheduledWakeTime, morningAlarm)
    }

    func testExpiredAlarmDoesNotBlockRestDayRefresh() async {
        var answers = SurveyAnswers()
        answers.wakeDays = []
        LuniferAlarm.shared.scheduledWakeTime = Date().addingTimeInterval(-60)

        let displayedAlarm = await LuniferAlarm.shared.refreshTomorrowAlarm(answers: answers)

        XCTAssertNil(displayedAlarm)
        XCTAssertNil(LuniferAlarm.shared.scheduledWakeTime)
    }

    func testExpiredAlarmIsNotReturnedWhenRepairSchedulingFails() async {
        var answers = SurveyAnswers()
        answers.wakeDays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        LuniferAlarm.shared.scheduledWakeTime = Date().addingTimeInterval(-60)
        UITestSupport.forceScheduleFailure = true

        let displayedAlarm = await LuniferAlarm.shared.refreshTomorrowAlarm(answers: answers)

        XCTAssertNil(displayedAlarm)
        XCTAssertNil(LuniferAlarm.shared.scheduledWakeTime)
        XCTAssertTrue(UITestSupport.didRejectSchedule)
    }

    func testPendingStopRescheduleSurvivesFailedRecovery() async {
        var answers = SurveyAnswers()
        answers.wakeDays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        AppPreferencesStore.shared.markPendingStopReschedule()
        UITestSupport.forceScheduleFailure = true

        let displayedAlarm = await LuniferAlarm.shared.refreshTomorrowAlarm(answers: answers)

        XCTAssertNil(displayedAlarm)
        XCTAssertNil(LuniferAlarm.shared.scheduledWakeTime)
        XCTAssertTrue(UITestSupport.didRejectSchedule)
        XCTAssertTrue(AppPreferencesStore.shared.hasPendingStopReschedule)
    }

    private func alarmAfterTomorrowsRestDay() throws -> (SurveyAnswers, Date) {
        let calendar = Calendar.current
        let day = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: Date())))
        let alarm = try XCTUnwrap(calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day))
        let weekdayIDs = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        var answers = SurveyAnswers()
        answers.wakeDays = [weekdayIDs[calendar.component(.weekday, from: day) - 1]]
        return (answers, alarm)
    }

    func testNightlyRefreshPreservesNextWakeDayAlarmAcrossRestDay() async throws {
        let (answers, nextAlarm) = try alarmAfterTomorrowsRestDay()
        LuniferAlarm.shared.scheduledWakeTime = nextAlarm

        let displayedAlarm = await LuniferAlarm.shared.refreshTomorrowAlarm(answers: answers)

        XCTAssertEqual(displayedAlarm, nextAlarm)
        XCTAssertEqual(LuniferAlarm.shared.scheduledWakeTime, nextAlarm)
    }

    func testRestDayRefreshRepairsMissingNextWakeDayAlarm() async throws {
        let (answers, _) = try alarmAfterTomorrowsRestDay()
        UITestSupport.forceScheduleFailure = true

        let displayedAlarm = await LuniferAlarm.shared.refreshTomorrowAlarm(answers: answers)

        XCTAssertNil(displayedAlarm)
        XCTAssertNil(LuniferAlarm.shared.scheduledWakeTime)
        XCTAssertTrue(UITestSupport.didRejectSchedule)
    }

    func testAdaptiveCheckPreservesNextWakeDayAlarmAcrossRestDay() async throws {
        let (answers, nextAlarm) = try alarmAfterTomorrowsRestDay()
        answers.saveToDefaults()
        LuniferAlarm.shared.scheduledWakeTime = nextAlarm

        await LuniferAlarm.shared.checkAlarmAgainstCalendar()

        XCTAssertEqual(LuniferAlarm.shared.scheduledWakeTime, nextAlarm)
    }

    func testRemovingFutureWakeDayStillCancelsItsAlarm() async throws {
        var (answers, nextAlarm) = try alarmAfterTomorrowsRestDay()
        answers.wakeDays = []
        LuniferAlarm.shared.scheduledWakeTime = nextAlarm

        let displayedAlarm = await LuniferAlarm.shared.refreshTomorrowAlarm(answers: answers)

        XCTAssertNil(displayedAlarm)
        XCTAssertNil(LuniferAlarm.shared.scheduledWakeTime)
    }
}
