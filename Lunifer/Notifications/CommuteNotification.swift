import Foundation
import UserNotifications

// ─────────────────────────────────────────────────────────────
// CommuteNotification
// ─────────────────────────────────────────────────────────────
// Manages two commute-related push notifications:
//
//  1. Leave Reminder — fires 15 minutes before the calculated
//     leave time, alerting the user they need to head out soon.
//
//  2. Delta Alert — fires immediately when the commute duration
//     changes by ≥5 minutes from the previously known value,
//     telling the user to leave earlier or that they have more
//     time. (Requires live routing in CommuteManager to produce
//     duration changes; currently duration is sourced from the
//     survey and will not change at runtime.)
//
// Both notifications respect the commuteReminderEnabled toggle
// in NotificationsSettingsView.

final class CommuteNotification {

    static let shared = CommuteNotification()

    private let leaveReminderID = "lunifer.commute.leave.reminder"
    private let deltaAlertID    = "lunifer.commute.delta.alert"

    private var isEnabled: Bool {
        // A missing key (first launch) is treated as enabled —
        // same pattern used by BatteryAlarmNotification.
        UserDefaults.standard.object(forKey: "commuteReminderEnabled") as? Bool != false
    }

    // ── Public API ────────────────────────────────────────────

    /// Schedules a "leave soon" reminder 15 minutes before leaveTime.
    /// Replaces any existing leave reminder.
    func scheduleLeaveReminder(leaveTime: Date) {
        guard isEnabled else {
            cancelLeaveReminder()
            return
        }

        let fireTime = leaveTime.addingTimeInterval(-15 * 60)
        guard fireTime > Date() else {
            print("⏭️ Commute leave reminder skipped — fire time is in the past")
            return
        }

        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let leaveStr = f.string(from: leaveTime)

        let content = UNMutableNotificationContent()
        content.title             = "Time to start getting ready"
        content.body              = "Leave by \(leaveStr) to arrive on time"
        content.sound             = .default
        content.interruptionLevel = .timeSensitive

        let comps   = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireTime
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [leaveReminderID])

        let request = UNNotificationRequest(
            identifier: leaveReminderID,
            content:    content,
            trigger:    trigger
        )
        center.add(request) { error in
            if let error {
                print("❌ Commute leave reminder failed: \(error.localizedDescription)")
            } else {
                print("🚗 Commute leave reminder set for \(f.string(from: fireTime)) (leave by \(leaveStr))")
            }
        }
    }

    /// Pushes an immediate alert when commute duration shifts by ≥5 minutes.
    /// - Parameters:
    ///   - newLeaveTime: The updated leave-by time derived from the new duration.
    ///   - didIncrease:  true if traffic got heavier, false if it cleared.
    func scheduleDeltaAlert(newLeaveTime: Date, didIncrease: Bool) {
        guard isEnabled else { return }

        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let timeStr = f.string(from: newLeaveTime)

        let content = UNMutableNotificationContent()
        if didIncrease {
            content.title = "Leave earlier — traffic is heavier"
            content.body  = "Leave by \(timeStr) to arrive on time"
        } else {
            content.title = "You have more time — traffic has cleared"
            content.body  = "You can leave by \(timeStr)"
        }
        content.sound             = .default
        content.interruptionLevel = .timeSensitive

        // UNTimeIntervalNotificationTrigger minimum is 1 second
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [deltaAlertID])

        let request = UNNotificationRequest(
            identifier: deltaAlertID,
            content:    content,
            trigger:    trigger
        )
        center.add(request) { error in
            if let error {
                print("❌ Commute delta alert failed: \(error.localizedDescription)")
            } else {
                print("🚗 Commute delta alert pushed — leave by \(timeStr), increased: \(didIncrease)")
            }
        }
    }

    /// Cancels the pending leave reminder without touching the delta alert.
    func cancelLeaveReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [leaveReminderID])
        print("🚗 Commute leave reminder cancelled")
    }

    /// Cancels all pending commute notifications.
    func cancelAll() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [leaveReminderID, deltaAlertID])
        print("🚗 All commute notifications cancelled")
    }
}
