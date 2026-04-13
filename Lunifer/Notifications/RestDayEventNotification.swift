import Foundation
import UserNotifications

// ─────────────────────────────────────────────────────────────
// RestDayEventNotification
// ─────────────────────────────────────────────────────────────
// Fires once per day when Lunifer detects that tomorrow is a
// scheduled rest day but the user has an early calendar event
// (starting before 10:00 AM).
//
// The notification asks the user whether they want Lunifer to
// set an alarm for them. Tapping "Wake me up" brings the app
// to the foreground and schedules the alarm (handled by
// LuniferNotificationDelegate). Tapping "Not needed" dismisses.
//
// Timing: fires at 7:00 PM the same evening, or immediately
// (1-second trigger) if the app is opened after 7:00 PM.
//
// Deduplication: only one notification is sent per calendar day.
// The last send date is stored under
// AppPreferencesStore.Keys.restDayNotificationSentDate.
//
// Category / action identifiers used by LuniferNotificationDelegate:
//   Category:  "lunifer.restday.event"
//   Wake action: "lunifer.restday.wakeup"
//   Dismiss action: "lunifer.restday.dismiss"

final class RestDayEventNotification {

    static let shared = RestDayEventNotification()

    // Identifiers — referenced by LuniferNotificationDelegate
    static let categoryID      = "lunifer.restday.event"
    static let wakeupActionID  = "lunifer.restday.wakeup"
    static let dismissActionID = "lunifer.restday.dismiss"

    private let notificationID = "lunifer.restday.event.prompt"

    // ── Public API ────────────────────────────────────────────

    /// Schedules the rest-day event notification if one hasn't
    /// already been sent today.
    ///
    /// - Parameters:
    ///   - event:   The early calendar event found for tomorrow.
    ///   - answers: Survey answers used to derive the wake time
    ///              (routine + commute offset from event start).
    func scheduleIfNeeded(event: CalendarEvent, answers: SurveyAnswers) {
        // Only prompt once per calendar day regardless of how many
        // times the app is opened.
        if let lastSent = UserDefaults.standard.object(
            forKey: AppPreferencesStore.Keys.restDayNotificationSentDate
        ) as? Date, Calendar.current.isDateInToday(lastSent) {
            print("💤 Rest-day event notification already sent today — skipping")
            return
        }

        // ── Derive alarm time from event start ─────────────────
        let routineMinutes = answers.routine.auto
            ? 60
            : answers.routine.hours * 60 + answers.routine.minutes
        let commuteMinutes: Int
        if answers.lifestyle == "student" || answers.lifestyle == "commuter" {
            commuteMinutes = answers.commute.auto
                ? 30
                : answers.commute.hours * 60 + answers.commute.minutes
        } else {
            commuteMinutes = 0
        }
        let wakeTime = event.startDate.addingTimeInterval(
            -Double(routineMinutes + commuteMinutes) * 60
        )

        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let eventTimeStr = f.string(from: event.startDate)
        let wakeTimeStr  = f.string(from: wakeTime)

        // ── Build content ──────────────────────────────────────
        let content = UNMutableNotificationContent()
        content.title             = "Early event tomorrow"
        content.body              = "\"\(event.title)\" starts at \(eventTimeStr). Want Lunifer to wake you at \(wakeTimeStr)?"
        content.sound             = .default
        content.interruptionLevel = .active
        content.categoryIdentifier = Self.categoryID
        // Attach the pre-calculated alarm time so the delegate can
        // schedule it without recomputing.
        content.userInfo = [
            "wakeTimestamp": wakeTime.timeIntervalSince1970,
            "eventTitle":    event.title
        ]

        // ── Pick fire time ─────────────────────────────────────
        // Aim for 7:00 PM. If it's already past 7 PM, fire within
        // a second so the user sees the prompt the same evening.
        let sevenPM = Calendar.current.date(
            bySettingHour: 19, minute: 0, second: 0, of: Date()
        )!
        let trigger: UNNotificationTrigger
        if Date() >= sevenPM {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            print("📅 Rest-day event notification firing immediately (past 7 PM)")
        } else {
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: sevenPM
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            print("📅 Rest-day event notification scheduled for \(f.string(from: sevenPM))")
        }

        // ── Schedule ───────────────────────────────────────────
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        let request = UNNotificationRequest(
            identifier: notificationID,
            content:    content,
            trigger:    trigger
        )
        center.add(request) { error in
            if let error {
                print("❌ Rest-day event notification failed: \(error.localizedDescription)")
            } else {
                // Record today as the last sent date to prevent duplicates.
                UserDefaults.standard.set(
                    Date(),
                    forKey: AppPreferencesStore.Keys.restDayNotificationSentDate
                )
            }
        }
    }

    /// Cancels any pending rest-day event prompt.
    func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID])
        print("💤 Rest-day event notification cancelled")
    }

    // ── Category registration ─────────────────────────────────

    /// Registers the UNNotificationCategory with its two action buttons.
    /// Call once at app launch from LuniferApp.init().
    static func registerCategory() {
        let wakeAction = UNNotificationAction(
            identifier: wakeupActionID,
            title:      "Wake me up",
            options:    [.foreground]   // brings app to foreground so alarm is scheduled
        )
        let dismissAction = UNNotificationAction(
            identifier: dismissActionID,
            title:      "Not needed",
            options:    [.destructive]
        )
        let category = UNNotificationCategory(
            identifier:         categoryID,
            actions:            [wakeAction, dismissAction],
            intentIdentifiers:  [],
            options:            []
        )
        // setNotificationCategories replaces all categories, so this is
        // the single place categories are declared for the app.
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
