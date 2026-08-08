import Foundation


final class AccountDataManager {
    static let shared = AccountDataManager()

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
        // Clear added-alarm storage so orphaned alarm cards don't appear on the next login
        UserDefaults.standard.removeObject(forKey: AppPreferencesStore.Keys.addedAlarms)
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

    func clearLocalAccountData() {
        AppPreferencesStore.shared.surveyCompleted = false
        clearLocalSessionDataOnSignOut()
    }
}
