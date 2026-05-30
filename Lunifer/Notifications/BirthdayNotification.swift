import Foundation
import UserNotifications
import FirebaseAuth

// ─────────────────────────────────────────────────────────────
// BirthdayNotification
// ─────────────────────────────────────────────────────────────
// Schedules a yearly "Happy Birthday" notification at 10 AM on
// the user's birthday (derived from their stored birth date).
//
// ── TIMING ───────────────────────────────────────────────────
// Fires at 10:00 AM in the user's local time zone on their
// birthday, repeating every year.
//
// ── NOTIFICATION FORMAT ──────────────────────────────────────
//   Title: "Happy Birthday {firstName}!"
//
// ── RESCHEDULING ─────────────────────────────────────────────
// Calling schedule() replaces any previously pending birthday
// notification, so updating age in Settings always stays in sync.

final class BirthdayNotification {

    static let shared = BirthdayNotification()
    private let notificationID = "lunifer.birthday"

    // ── Public API ────────────────────────────────────────────

    /// Schedules a yearly birthday notification at 10 AM.
    ///
    /// - Parameter answers: The user's survey answers. `answers.age` must be
    ///   a "yyyy-MM-dd" birthday string for this to do anything — plain integer
    ///   legacy values are silently ignored.
    func schedule(answers: SurveyAnswers) async {
        // Parse birthday — requires "yyyy-MM-dd" format stored by DatePicker in Settings
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let birthday = formatter.date(from: answers.age) else {
            // Legacy plain-integer age value — no date available, skip
            return
        }

        // Permission check
        let center   = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else {
            print("⏭️ Birthday notification skipped — notifications not authorised")
            return
        }

        // ── Derive first name ─────────────────────────────────
        let displayName = Auth.auth().currentUser?.displayName ?? ""
        let firstName   = displayName.components(separatedBy: " ").first ?? ""
        let title       = firstName.isEmpty ? "Happy Birthday!" : "Happy Birthday \(firstName)!"

        // ── Build notification content ────────────────────────
        let content = UNMutableNotificationContent()
        content.title            = title
        content.sound            = .default
        content.interruptionLevel = .active

        // ── Build yearly trigger (month + day at 10:00 AM) ────
        let birthdayComps = Calendar.current.dateComponents([.month, .day], from: birthday)
        var triggerComps  = DateComponents()
        triggerComps.month  = birthdayComps.month
        triggerComps.day    = birthdayComps.day
        triggerComps.hour   = 10
        triggerComps.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: true)

        // Replace any existing birthday notification
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            print("🎂 Birthday notification scheduled for \(birthdayComps.month ?? 0)/\(birthdayComps.day ?? 0) at 10:00 AM (yearly)")
        } catch {
            print("❌ Birthday notification failed to schedule: \(error.localizedDescription)")
        }
    }

    /// Cancels any pending birthday notification.
    func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID])
        print("🎂 Birthday notification cancelled")
    }
}
