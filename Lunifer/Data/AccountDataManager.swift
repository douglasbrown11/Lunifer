import Foundation
import BackgroundTasks
import UIKit
import UserNotifications


final class AccountDataManager {
    static let shared = AccountDataManager()

    private var shutdownTask: Task<Void, Never>?

    /// Stops device activity before clearing the signed-out account's data.
    func stopAllBackgroundActivity() async {
        if let shutdownTask {
            await shutdownTask.value
            return
        }
        BackgroundActivitySession.shared.stop()
        let task = Task { @MainActor in
            SleepTracker.shared.stopTracking()
            LuniferAlarm.shared.stopAdaptiveRescheduling()
            LuniferAlarm.shared.stopMonitoring()
            CommuteManager.shared.stopPolling()
            BatteryAlarmNotification.shared.stopMonitoring()
            HealthKitManager.shared.disconnect()
            MorningRoutineEstimator.shared.clearLocalData()
            LocationManager.shared.stop()
            BGTaskScheduler.shared.cancelAllTaskRequests()
            UIApplication.shared.unregisterForRemoteNotifications()
            await LuniferAlarm.shared.cancelAlarm()
            await LuniferAlarm.shared.cancelAllAddedAlarms()
            let notifications = UNUserNotificationCenter.current()
            notifications.removeAllPendingNotificationRequests()
            notifications.removeAllDeliveredNotifications()
            let requests = await URLSession.shared.allTasks
            requests.forEach { $0.cancel() }
        }
        shutdownTask = task
        await task.value
        shutdownTask = nil
    }

    @MainActor
    func clearLocalSessionDataOnSignOut() {
        SurveyAnswersStore.shared.clearLocalData()
        SleepHistoryStore.shared.clearLocalData()
        SleepTrackingStore.shared.clearLocalData()
        AdaptiveAlarmStore.shared.clearLocalData()
        MorningRoutineEstimator.clearStoredData()
        HealthKitManager.clearStoredData()
        CalendarNudgeNotification.clearStoredData()
        SilentPushManager.clearStoredData()
        // Clear Outlook (Microsoft Graph) calendar tokens so they don't leak to
        // the next account on this device. Google calendar access rides on the
        // GIDSignIn session, which is cleared on sign-out separately.
        MicrosoftCalendarService.clearStoredData()
        AppPreferencesStore.shared.resetBatteryMonitoringState()
        AppPreferencesStore.shared.resetAlarmOverride()
        UserDefaults.standard.removeObject(forKey: AppPreferencesStore.Keys.calculatedAlarmTimestamp)
        AppPreferencesStore.shared.clearRestDayAlarmOptIn()
        AppPreferencesStore.shared.clearPendingStopReschedule()
        AppPreferencesStore.shared.clearFinalizedMainAlarm()
        // Clear added-alarm storage so orphaned alarm cards don't appear on the next login
        UserDefaults.standard.removeObject(forKey: AppPreferencesStore.Keys.addedAlarms)
        LuniferAlarm.shared.clearAddedAlarmIdentityState()
        // NOTE: hasSeenWalkthrough is intentionally NOT cleared here. Resetting it on
        // sign-out re-triggered the coach-mark tour for RETURNING users who signed back
        // in (they skip the survey and land straight on the dashboard with the flag
        // freshly cleared). The flag is instead reset on survey completion in
        // Survey.swift's handleFinish(), so only a user who actually onboards sees it.
        // Clear the feedback slowmode timestamp so the daily limit doesn't carry
        // over to the next account signing in on this device.
        UserDefaults.standard.removeObject(forKey: AppPreferencesStore.Keys.lastFeedbackSubmittedDate)
        // Clear WHOOP tokens and prefs
        KeychainHelper.delete(forKey: KeychainHelper.Keys.whoopAccessToken)
        KeychainHelper.delete(forKey: KeychainHelper.Keys.whoopRefreshToken)
        AppPreferencesStore.shared.resetWhoopData()
        // Clear Oura tokens and prefs
        KeychainHelper.delete(forKey: KeychainHelper.Keys.ouraAccessToken)
        KeychainHelper.delete(forKey: KeychainHelper.Keys.ouraRefreshToken)
        AppPreferencesStore.shared.resetOuraData()
    }

    @MainActor
    func clearLocalAccountData() {
        AppPreferencesStore.shared.surveyCompleted = false
        clearLocalSessionDataOnSignOut()
    }
}
