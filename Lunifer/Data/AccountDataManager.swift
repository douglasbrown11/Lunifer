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
        // Clear Outlook (Microsoft Graph) calendar tokens so they don't leak to
        // the next account on this device. Google calendar access rides on the
        // GIDSignIn session, which is cleared on sign-out separately.
        MicrosoftCalendarService.clearStoredData()
        AppPreferencesStore.shared.resetBatteryMonitoringState()
        AppPreferencesStore.shared.resetAlarmOverride()
        // Clear added-alarm storage so orphaned alarm cards don't appear on the next login
        UserDefaults.standard.removeObject(forKey: AppPreferencesStore.Keys.addedAlarms)
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
