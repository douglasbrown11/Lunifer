import Foundation
import UserNotifications

// ─────────────────────────────────────────────────────────────
// WakeNotification
// ─────────────────────────────────────────────────────────────
// Schedules a "heads up" notification 3 hours before the user's
// estimated bedtime, telling them what time Lunifer will wake
// them up the next morning.
//
// ── TIMING ───────────────────────────────────────────────────
// Estimated bedtime = wakeTime − user's sleep duration
// Notification fires 3 hours before that bedtime so the user
// still has time to wind down.
//
//   Example: wake at 7:00 AM, sleeps 8h → bedtime 11:00 PM
//   Notification fires at 8:00 PM
//
// ── NOTIFICATION FORMAT ──────────────────────────────────────
//   Title:  "11:00 PM → 7:00 AM"
//   Body:   "Lunifer is waking you up at 7:00 AM tomorrow"
//
// ── RESCHEDULING ─────────────────────────────────────────────
// Calling schedule() cancels any previously pending wake
// reminder and replaces it, so overriding the alarm time from
// the dashboard always keeps the notification in sync.

final class WakeNotification {

    static let shared = WakeNotification()
    private let notificationID = "lunifer.wake.reminder"

    // ── Public API ────────────────────────────────────────────

    /// Schedules the wake reminder notification.
    ///
    /// - Parameters:
    ///   - wakeDate: The calculated or user-overridden alarm time. If this
    ///               date is already in the past (today's alarm already fired),
    ///               it is automatically advanced to tomorrow.
    ///   - answers:  The user's survey answers, used to derive sleep duration.
    func schedule(wakeDate: Date, answers: SurveyAnswers) async {
        // Respect the user's toggle — cancel any pending reminder and bail if disabled
        guard UserDefaults.standard.object(forKey: "wakeReminderEnabled") as? Bool != false else {
            cancel()
            return
        }

        // Advance to tomorrow if today's alarm has already passed
        let targetWake: Date
        if wakeDate < Date() {
            targetWake = Calendar.current.date(byAdding: .day, value: 1, to: wakeDate) ?? wakeDate
        } else {
            targetWake = wakeDate
        }

        // ── Derive sleep duration ─────────────────────────────
        // Mirrors the same logic used in LuniferMain.bedtimeString
        // and BatteryAlarmNotification.expectedSleepDuration().
        let sleepHours: Double
        if answers.sleep.auto {
            sleepHours = SleepDurationModel.baselineForAge(answers.age)
        } else {
            sleepHours = Double(answers.sleep.hours) + Double(answers.sleep.minutes) / 60.0
        }

        // ── Compute bedtime and notification fire time ────────
        let bedtime    = targetWake.addingTimeInterval(-sleepHours * 3600)
        let notifyAt   = bedtime.addingTimeInterval(-3 * 3600)

        // Nothing to do if the notification window has already passed
        guard notifyAt > Date() else {
            print("⏭️ Wake reminder skipped — fire time is in the past")
            return
        }

        // ── Permission check ──────────────────────────────────
        let center   = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else {
            print("⏭️ Wake reminder skipped — notifications not authorised")
            return
        }

        // ── Format display strings ────────────────────────────
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let bedtimeStr = f.string(from: bedtime)
        let wakeStr    = f.string(from: targetWake)

        // ── Build notification content ────────────────────────
        let content = UNMutableNotificationContent()
        content.title            = "\(bedtimeStr) \u{2192} \(wakeStr)"   // e.g. "11:00 PM → 7:00 AM"
        content.body             = "Lunifer is waking you up at \(wakeStr) tomorrow"
        content.sound            = .default
        content.interruptionLevel = .passive   // shows quietly, no full-screen interrupt

        // ── Schedule ──────────────────────────────────────────
        let comps   = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: notifyAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        // Replace any existing wake reminder
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            print("🌙 Wake reminder scheduled for \(f.string(from: notifyAt)) " +
                  "(bedtime \(bedtimeStr), wake \(wakeStr))")
        } catch {
            print("❌ Wake reminder failed to schedule: \(error.localizedDescription)")
        }
    }

    /// Cancels any pending wake reminder (e.g. when the user disables Lunifer).
    func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID])
        print("🌙 Wake reminder cancelled")
    }
}
