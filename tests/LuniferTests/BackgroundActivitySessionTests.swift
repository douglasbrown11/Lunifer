import XCTest
import UIKit
import BackgroundTasks
import UserNotifications
@testable import Lunifer

@MainActor
final class BackgroundActivitySessionTests: XCTestCase {
    override func tearDown() async throws {
        BackgroundActivitySession.shared.resume()
    }

    func testSignOutRejectsOldWorkEvenAfterSignIn() {
        let session = BackgroundActivitySession()
        let old = session.generation
        XCTAssertTrue(session.accepts(old))
        session.stop()
        XCTAssertFalse(session.accepts(old))
        session.resume()
        XCTAssertFalse(session.accepts(old))
        XCTAssertTrue(session.accepts(session.generation))
    }

    func testRepeatedResumeKeepsCurrentTrackingSession() {
        let session = BackgroundActivitySession()
        let generation = session.generation
        session.resume()
        session.resume()
        XCTAssertTrue(session.accepts(generation))
    }

    func testShutdownStopsServicesAndBlocksLateTrackingStart() async {
        await AccountDataManager.shared.stopAllBackgroundActivity()
        XCTAssertTrue(BackgroundActivitySession.shared.isStopped)
        XCTAssertFalse(SleepTracker.shared.isTracking)
        XCTAssertFalse(UIDevice.current.isBatteryMonitoringEnabled)
        XCTAssertFalse(HealthKitManager.shared.isConnected)
        let requests = await BGTaskScheduler.shared.pendingTaskRequests()
        XCTAssertTrue(requests.isEmpty)
        let notifications = await UNUserNotificationCenter.current().pendingNotificationRequests()
        XCTAssertTrue(notifications.isEmpty)
        await SleepTracker.shared.startTracking()
        XCTAssertFalse(SleepTracker.shared.isTracking)
        await AccountDataManager.shared.stopAllBackgroundActivity()
        XCTAssertFalse(SleepTracker.shared.isTracking)
    }
}
