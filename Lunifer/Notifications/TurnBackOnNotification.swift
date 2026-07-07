import Foundation
import UserNotifications

// ─────────────────────────────────────────────────────────────
// TurnBackOnNotification
// ─────────────────────────────────────────────────────────────
// Schedules a one-shot notification that fires 7 days after
// Lunifer's alarm is turned off, prompting the user to re-enable it.
//
// ── USAGE ────────────────────────────────────────────────────
// Call schedule() whenever the alarm is disabled or the app
// detects the alarm has been inactive. Call cancel() as soon
// as the alarm is turned back on so the notification never
// reaches the user unnecessarily.
//
// ── TIMING ───────────────────────────────────────────────────
// Fires 7 days (604800 seconds) after schedule() is called.
// Non-repeating — fires once and is removed automatically.
//
// ── NOTIFICATION FORMAT ──────────────────────────────────────
//   Title: "The nights have been quiet"
//   Body:  "It's been a week since Lunifer was on. Tap to pick
//           back up where you left off."

final class TurnBackOnNotification {

    static let shared = TurnBackOnNotification()
    private init() {}

    private let notificationID = "lunifer.reengagement"
    private let intervalSeconds: TimeInterval = 7 * 24 * 3600   // 7 days

    // ── Public API ────────────────────────────────────────────

    /// Schedules a re-engagement notification to fire in 7 days.
    ///
    /// Replaces any previously pending re-engagement notification,
    /// so calling this multiple times safely resets the countdown.
    func schedule() async {
        let center   = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else {
            print("⏭️ Re-engagement notification skipped — notifications not authorised")
            return
        }

        // ── Build notification content ────────────────────────
        let content        = UNMutableNotificationContent()
        content.title      = "The nights have been quiet"
        content.body       = "It's been a week since Lunifer was on. Tap to pick back up where you left off."
        content.sound      = .default
        content.interruptionLevel = .active

        // ── Build one-shot trigger (fires once after 7 days) ──
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: intervalSeconds,
            repeats: false
        )

        // Replace any existing pending re-engagement notification
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            print("💤 Re-engagement notification scheduled — fires in 7 days")
        } catch {
            print("❌ Re-engagement notification failed to schedule: \(error.localizedDescription)")
        }
    }

    /// Cancels any pending re-engagement notification.
    ///
    /// Call this as soon as the user re-enables the alarm so the
    /// notification is never delivered unnecessarily.
    func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID])
        print("💤 Re-engagement notification cancelled")
    }
}
