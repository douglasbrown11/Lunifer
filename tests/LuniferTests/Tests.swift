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
    private let keys = ["luniferEnabled", "overrideActive", "surveyAnswers", "restDayAlarmOptInDate"]

    override func setUp() async throws {
        for key in keys {
            savedDefaults[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: "luniferEnabled")
        LuniferAlarm.shared.scheduledWakeTime = nil
        LuniferAlarm.shared.activeAlarms = []
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
