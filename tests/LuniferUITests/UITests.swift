//
//  LuniferUITests.swift
//  LuniferUITests
//
//  Created by Douglas Brown on 3/11/26.
//

import XCTest

final class LuniferUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testTurningLuniferBackOnSchedulesAlarmImmediately() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-dashboard"]
        app.launch()
        defer { app.terminate() }
        let toggle = app.buttons["lunifer.enabledToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForAlarmStatus("Alarm scheduled", toggle: toggle), "Dashboard launch must first create a real AlarmKit alarm.")

        toggle.tap()
        XCTAssertTrue(waitForAlarmStatus("No scheduled alarms", toggle: toggle), "Turning off must remove the AlarmKit alarm.")
        toggle.tap()
        XCTAssertTrue(waitForAlarmStatus("Alarm scheduled", toggle: toggle), "Turning back on must immediately restore an AlarmKit alarm.")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Alarm restored after re-enabling"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // Resolve the visible label again after the button travels back down.
        app.staticTexts["Turn Lunifer off"].tap()
        XCTAssertTrue(waitForAlarmStatus("No scheduled alarms", toggle: toggle))
    }

    @MainActor
    func testFailedReplacementPreservesExistingAlarmAfterReopening() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-dashboard"]
        app.launch()
        defer { app.terminate() }
        let toggle = app.buttons["lunifer.enabledToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForAlarmStatus("Alarm scheduled", toggle: toggle))
        app.terminate()

        // Reopening refreshes tomorrow's alarm using the real AlarmKit registry.
        // Reject only the new scheduling request, as an OS scheduling error would.
        app.launchArguments = ["--ui-test-dashboard", "--ui-test-fail-scheduling"]
        app.launch()
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForAlarmStatus("Replacement failed; Alarm scheduled", toggle: toggle), "The previous AlarmKit alarm must survive a failed replacement.")
        app.terminate()
        app.launchArguments = ["--ui-test-dashboard"]
        app.launch()
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForAlarmStatus("Alarm scheduled", toggle: toggle), "Successful replacement must leave exactly one alarm, not duplicate wakeups.")
        app.staticTexts["Turn Lunifer off"].tap()
        XCTAssertTrue(waitForAlarmStatus("No scheduled alarms", toggle: toggle))
    }

    @MainActor
    func testDeniedAlarmPermissionShowsSettingsPage() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-dashboard", "--ui-test-denied-alarm"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["alarmPermission.title"].waitForExistence(timeout: 15))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Alarm permission recovery page"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertFalse(app.buttons["lunifer.enabledToggle"].exists, "Home controls must be covered while alarm permission is denied.")
        app.swipeRight()
        let insightsTitle = app.staticTexts["RECOMMENDED SLEEP"]
        XCTAssertTrue(insightsTitle.waitForExistence(timeout: 10), "Sleep Insights must remain reachable by swiping.")
        XCTAssertTrue(insightsTitle.isHittable, "Sleep Insights must be visible, not merely loaded offscreen.")
        let insightsScreenshot = XCTAttachment(screenshot: app.screenshot())
        insightsScreenshot.name = "Sleep Insights reachable while alarm access is off"
        insightsScreenshot.lifetime = .keepAlways
        add(insightsScreenshot)
        // Swipe above the horizontally scrolling sleep-history chart so the
        // gesture pages the dashboard rather than scrolling the chart itself.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2)))
        XCTAssertTrue(app.staticTexts["alarmPermission.title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["alarmPermission.title"].isHittable)
        app.buttons["alarmPermission.openSettings"].tap()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
        let settingsScreenshot = XCTAttachment(screenshot: settings.screenshot())
        settingsScreenshot.name = "Lunifer Settings destination"
        settingsScreenshot.lifetime = .keepAlways
        add(settingsScreenshot)
        app.activate()
        XCTAssertTrue(app.staticTexts["alarmPermission.title"].waitForExistence(timeout: 10), "Keep the recovery page visible while permission remains denied.")
    }

    @MainActor
    private func waitForAlarmStatus(_ expected: String, toggle: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(30)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var settledSince: Date?
        repeat {
            let alert = springboard.alerts.firstMatch
            if alert.exists {
                for label in ["Allow", "OK", "Allow While Using App"] where alert.buttons[label].exists {
                    alert.buttons[label].tap()
                    break
                }
            }
            if toggle.exists, toggle.isEnabled, toggle.isHittable, toggle.value as? String == expected {
                // The toggle moves for 0.5 seconds when enablement changes.
                // Wait for it to settle before a subsequent coordinate tap.
                if let settledSince, Date().timeIntervalSince(settledSince) >= 0.6 { return true }
                if settledSince == nil { settledSince = Date() }
            } else {
                settledSince = nil
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return false
    }
}
