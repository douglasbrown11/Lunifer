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
            // Recompute the wake time NOW rather than using the value frozen into the
            // notification at schedule time: resolve tomorrow's baseline live (4-step
            // fallback chain, fresh calendar + routine/commute) and apply the adaptive
            // bandit offset, so this alarm is adaptive like every other calculated alarm.
            // The frozen `wakeTimestamp` is kept only as a fallback for when saved
            // survey answers can't be loaded.
            let frozenWake = (userInfo["wakeTimestamp"] as? TimeInterval)
                .map { Date(timeIntervalSince1970: $0) }
            Task { @MainActor in
                // Make sure Lunifer is switched on for the night.
                UserDefaults.standard.set(true, forKey: AppPreferencesStore.Keys.luniferEnabled)

                await LuniferAlarm.shared.requestAuthorization()

                let answers = SurveyAnswers.loadFromDefaults()
                let wakeDate: Date

                if let answers {
                    let tomorrow = Calendar.current.date(
                        byAdding: .day, value: 1,
                        to: Calendar.current.startOfDay(for: Date())
                    ) ?? Date()
                    // Baseline resolution + adaptive offset, mirroring the dashboard /
                    // scheduleNextWakeAlarm path so the pending adaptive decision is saved.
                    let baseline = await LuniferAlarm.shared.resolveBaselineAlarmDate(
                        answers: answers, targetDay: tomorrow
                    )
                    let finalAlarm = LuniferAlarm.shared.decideAlarm(from: baseline, answers: answers)

                    // Mark this rest day as an explicit opt-in so the rest-day
                    // cancel guards (dashboard load + checkAndAdaptAlarm) leave this
                    // alarm in place instead of cancelling it. Set before scheduling
                    // so a guard racing the schedule already sees the opt-in.
                    AppPreferencesStore.shared.setRestDayAlarmOptIn(for: finalAlarm)

                    // Keep the wake reminder in sync with the adaptive alarm.
                    await WakeNotification.shared.schedule(wakeDate: finalAlarm, answers: answers)

                    await LuniferAlarm.shared.scheduleAlarm(
                        for: finalAlarm,
                        eventTitle: baseline.firstEvent?.title ?? "your first event",
                        routineMinutes: baseline.routineMinutes,
                        commuteMinutes: baseline.commuteMinutes
                    )
                    wakeDate = finalAlarm
                } else if let frozenWake {
                    // No saved answers — fall back to the pre-computed (non-adaptive) time.
                    AppPreferencesStore.shared.setRestDayAlarmOptIn(for: frozenWake)
                    await LuniferAlarm.shared.scheduleAlarm(for: frozenWake)
                    wakeDate = frozenWake
                } else {
                    print("⚠️ Rest-day wake action: no answers and missing wakeTimestamp")
                    return
                }

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
