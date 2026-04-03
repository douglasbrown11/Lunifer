import Foundation

final class AccountDataManager {
    static let shared = AccountDataManager()

    func clearLocalSessionDataOnSignOut() {
        SurveyAnswersStore.shared.clearLocalData()
        SleepHistoryStore.shared.clearLocalData()
        SleepTrackingStore.shared.clearLocalData()
        AppPreferencesStore.shared.resetBatteryMonitoringState()
        AppPreferencesStore.shared.resetHomeLocation()
        AppPreferencesStore.shared.resetAlarmOverride()
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
