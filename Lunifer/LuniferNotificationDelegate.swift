import Foundation
import UserNotifications

// ─────────────────────────────────────────────────────────────
// LuniferNotificationDelegate
// ─────────────────────────────────────────────────────────────
// Single UNUserNotificationCenterDelegate for the entire app.
//
// Responsibilities:
//
//  1. willPresent — makes notifications visible as banners even
//     when the app is already in the foreground (e.g. the wake
//     reminder showing while the user is on the dashboard).
//
//  2. didReceive — handles actionable notification taps:
//
//     ┌─ Rest-day event prompt (RestDayEventNotification) ─────┐
//     │  "Wake me up"  → schedules alarm at the pre-computed   │
//     │                  wake time stored in notification's     │
//     │                  userInfo["wakeTimestamp"].             │
//     │  "Not needed"  → no-op (notification auto-dismisses).  │
//     └────────────────────────────────────────────────────────┘
//
// Assigned to UNUserNotificationCenter.current().delegate in
// LuniferApp.init() via the shared singleton below.

final class LuniferNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    static let shared = LuniferNotificationDelegate()

    // ── Foreground presentation ───────────────────────────────

    /// Show banner + play sound even while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // ── Action handling ───────────────────────────────────────

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionID = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo

        switch actionID {

        case RestDayEventNotification.wakeupActionID:
            // User wants Lunifer to wake them tomorrow despite it being a rest day.
            // The pre-calculated alarm time was embedded in userInfo at schedule time.
            guard let timestamp = userInfo["wakeTimestamp"] as? TimeInterval else {
                print("⚠️ Rest-day wake action: missing wakeTimestamp in userInfo")
                break
            }
            let wakeDate = Date(timeIntervalSince1970: timestamp)
            Task { @MainActor in
                // Make sure Lunifer is switched on for the night.
                UserDefaults.standard.set(true, forKey: AppPreferencesStore.Keys.luniferEnabled)

                await LuniferAlarm.shared.requestAuthorization()

                // Schedule the wake reminder notification in sync with the alarm.
                if let answers = SurveyAnswers.loadFromDefaults() {
                    await WakeNotification.shared.schedule(wakeDate: wakeDate, answers: answers)
                }

                await LuniferAlarm.shared.scheduleAlarm(for: wakeDate)
                print("⏰ Rest-day alarm scheduled for \(wakeDate.formatted(date: .omitted, time: .shortened))")
            }

        case RestDayEventNotification.dismissActionID:
            // User doesn't need an alarm — nothing to do.
            print("💤 Rest-day event notification dismissed by user")

        default:
            // Default tap (no action button) — app just opens, nothing extra needed.
            break
        }

        completionHandler()
    }
}
