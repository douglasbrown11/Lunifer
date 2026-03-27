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
    }
}
