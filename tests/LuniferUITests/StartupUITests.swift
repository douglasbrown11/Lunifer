import XCTest

@MainActor
final class StartupUITests: XCTestCase {
    func testDelayedSessionSyncDoesNotReopenSplash() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-dashboard", "--ui-test-returning-session"]
        app.launch()
        defer { app.terminate() }
        let home = app.buttons["lunifer.enabledToggle"]
        XCTAssertTrue(home.waitForExistence(timeout: 6))
        // The saved-session upload completes after home is already visible.
        let reopened = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: home)
        XCTAssertEqual(XCTWaiter.wait(for: [reopened], timeout: 8), .timedOut,
                       "A delayed session upload must not send home back to the splash.")
    }

    func testRestoredSessionDoesNotWaitForUploadToShowHome() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-dashboard", "--ui-test-returning-session",
                               "--ui-test-session-listener-only"]
        app.launch()
        defer { app.terminate() }
        // Auth restored after initial appearance: the upload still takes eight
        // seconds, but the returning user only waits for the three-second splash.
        XCTAssertTrue(app.buttons["lunifer.enabledToggle"].waitForExistence(timeout: 5))
    }

    func testReturningSessionResumesWithoutRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-dashboard", "--ui-test-returning-session"]
        app.launch()
        defer { app.terminate() }
        XCUIDevice.shared.press(.home)
        // Accelerate an idle interval: let the splash deadline and upload elapse
        // while backgrounded, then resume the same process.
        let idle = XCTestExpectation(description: "background interval")
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { idle.fulfill() }
        wait(for: [idle], timeout: 12)
        app.activate()
        XCTAssertTrue(app.buttons["lunifer.enabledToggle"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Home after resuming returning session"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
