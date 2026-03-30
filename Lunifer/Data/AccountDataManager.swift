import Foundation

final class AccountDataManager {
    static let shared = AccountDataManager()

    func clearLocalAccountData() {
        AppPreferencesStore.shared.surveyCompleted = false
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
    }
}
