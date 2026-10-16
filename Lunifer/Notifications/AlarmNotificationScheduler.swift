import Foundation
import UserNotifications

/// Serializes submissions so an obsolete operation cannot remove a newer reminder.
@MainActor
final class AlarmNotificationScheduler {
    private let identifier: String
    private let preferenceKey: String
    private var revision = UUID()
    private var submission: Task<Bool, Never>?

    init(identifier: String, preferenceKey: String) {
        self.identifier = identifier
        self.preferenceKey = preferenceKey
    }

    private var isEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: AppPreferencesStore.Keys.luniferEnabled) as? Bool != false
            && defaults.object(forKey: "allNotificationsEnabled") as? Bool != false
            && defaults.object(forKey: preferenceKey) as? Bool != false
    }

    @discardableResult
    func schedule(content: UNMutableNotificationContent, trigger: UNNotificationTrigger?) async -> Bool {
        guard isEnabled else { cancel(); return false }
        let revision = self.revision
        let generation = BackgroundActivitySession.shared.generation
        let previous = submission
        let task = Task { @MainActor in
            _ = await previous?.value
            let center = UNUserNotificationCenter.current()
            @MainActor func isCurrent() -> Bool {
                self.revision == revision && self.isEnabled
                    && BackgroundActivitySession.shared.accepts(generation)
            }
            guard isCurrent() else { return false }
            let settings = await center.notificationSettings()
            #if DEBUG
            if self.identifier == "lunifer.wake.reminder" {
                await UITestSupport.wakeReminderPause?()
            }
            #endif
            guard isCurrent(), settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return false }
            let request = UNNotificationRequest(identifier: self.identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
                #if DEBUG
                if self.identifier == "lunifer.wake.reminder" {
                    await UITestSupport.wakeReminderAfterAdd?()
                }
                #endif
                if !isCurrent() {
                    center.removePendingNotificationRequests(withIdentifiers: [self.identifier])
                    center.removeDeliveredNotifications(withIdentifiers: [self.identifier])
                    return false
                }
                return true
            } catch {
                print("Notification scheduling failed for \(self.identifier): \(error.localizedDescription)")
                return false
            }
        }
        submission = task
        return await task.value
    }

    /// Invalidate every ordinary alert, preserving the separate seven-day reminder.
    static func cancelOrdinaryNotifications() {
        WakeNotification.shared.cancel()
        BatteryAlarmNotification.shared.cancelWarning()
        CommuteNotification.shared.cancelAll()
        CalendarNudgeNotification.shared.cancel()
        RestDayEventNotification.shared.cancel()
    }

    /// Invalidate suspended submissions before asking iOS to remove their notifications.
    func cancel() {
        revision = UUID()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
