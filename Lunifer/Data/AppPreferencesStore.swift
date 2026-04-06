import Foundation

final class AppPreferencesStore {
    static let shared = AppPreferencesStore()

    enum Keys {
        static let surveyCompleted = "surveyCompleted"

        // Alarm
        static let snoozeMinutes = "snoozeMinutes"
        static let selectedAlarmSound = "selectedAlarmSound"
        static let luniferEnabled = "luniferEnabled"
        static let overrideActive = "overrideActive"
        static let overrideTimestamp = "overrideTimestamp"

        // Added alarm
        static let addedAlarmActive = "addedAlarmActive"
        static let addedAlarmTimestamp = "addedAlarmTimestamp"
        static let addedAlarmSound = "addedAlarmSound"
        static let addedAlarmLabel = "addedAlarmLabel"
        static let addedAlarmSnoozeMinutes = "addedAlarmSnoozeMinutes"

        // Home location
        static let homeLatitude = "homeLatitude"
        static let homeLongitude = "homeLongitude"
        static let homeLocationSet = "homeLocationSet"
        static let homeLocationName = "homeLocationName"

        // WHOOP integration
        static let whoopConnected = "whoopConnected"
        static let whoopRecommendedSleepHours = "whoopRecommendedSleepHours"
        static let whoopLastSyncDate = "whoopLastSyncDate"
        static let whoopTokenExpiry = "whoopTokenExpiry"
        static let whoopLatestSleepOnset = "whoopLatestSleepOnset"
        static let whoopLatestWakeTime = "whoopLatestWakeTime"

        // Oura integration
        static let ouraConnected = "ouraConnected"
        static let ouraRecommendedSleepHours = "ouraRecommendedSleepHours"
        static let ouraLastSyncDate = "ouraLastSyncDate"
        static let ouraLatestSleepOnset = "ouraLatestSleepOnset"
        static let ouraLatestWakeTime = "ouraLatestWakeTime"

        // Notifications
        static let batteryAlertEnabled    = "batteryAlertEnabled"
        static let wakeReminderEnabled    = "wakeReminderEnabled"
        static let commuteReminderEnabled = "commuteReminderEnabled"

        // Commute polling state (persisted for background task continuity)
        static let commuteArrivalTimestamp        = "commuteArrivalTimestamp"
        static let commutePreviousDurationMinutes = "commutePreviousDurationMinutes"
        static let commutePollingActive           = "commutePollingActive"

        // Battery monitoring internals
        static let batteryDrainSamples = "lunifer_battery_drain_samples"
        static let batteryLastCheckTime = "lunifer_battery_last_check_time"
        static let batteryLastCheckLevel = "lunifer_battery_last_check_level"
        static let batteryLastWarnedAlarm = "lunifer_battery_last_warned_alarm"
    }

    private let defaults = UserDefaults.standard

    var surveyCompleted: Bool {
        get { defaults.bool(forKey: Keys.surveyCompleted) }
        set { defaults.set(newValue, forKey: Keys.surveyCompleted) }
    }

    func resetBatteryMonitoringState() {
        defaults.removeObject(forKey: Keys.batteryDrainSamples)
        defaults.removeObject(forKey: Keys.batteryLastCheckTime)
        defaults.removeObject(forKey: Keys.batteryLastCheckLevel)
        defaults.removeObject(forKey: Keys.batteryLastWarnedAlarm)
    }

    func resetHomeLocation() {
        defaults.removeObject(forKey: Keys.homeLatitude)
        defaults.removeObject(forKey: Keys.homeLongitude)
        defaults.set(false, forKey: Keys.homeLocationSet)
        defaults.removeObject(forKey: Keys.homeLocationName)
    }

    func resetAlarmOverride() {
        defaults.set(false, forKey: Keys.overrideActive)
        defaults.removeObject(forKey: Keys.overrideTimestamp)
    }

    // MARK: - WHOOP

    var whoopConnected: Bool {
        get { defaults.bool(forKey: Keys.whoopConnected) }
        set { defaults.set(newValue, forKey: Keys.whoopConnected) }
    }

    var whoopRecommendedSleepHours: Double {
        get { defaults.double(forKey: Keys.whoopRecommendedSleepHours) }
        set { defaults.set(newValue, forKey: Keys.whoopRecommendedSleepHours) }
    }

    var whoopLastSyncDate: Date? {
        get { defaults.object(forKey: Keys.whoopLastSyncDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.whoopLastSyncDate) }
    }

    var whoopTokenExpiry: Date? {
        get { defaults.object(forKey: Keys.whoopTokenExpiry) as? Date }
        set { defaults.set(newValue, forKey: Keys.whoopTokenExpiry) }
    }

    var whoopLatestSleepOnset: Date? {
        get { defaults.object(forKey: Keys.whoopLatestSleepOnset) as? Date }
        set { defaults.set(newValue, forKey: Keys.whoopLatestSleepOnset) }
    }

    var whoopLatestWakeTime: Date? {
        get { defaults.object(forKey: Keys.whoopLatestWakeTime) as? Date }
        set { defaults.set(newValue, forKey: Keys.whoopLatestWakeTime) }
    }

    func resetWhoopData() {
        defaults.set(false, forKey: Keys.whoopConnected)
        defaults.set(0.0, forKey: Keys.whoopRecommendedSleepHours)
        defaults.removeObject(forKey: Keys.whoopLastSyncDate)
        defaults.removeObject(forKey: Keys.whoopTokenExpiry)
        defaults.removeObject(forKey: Keys.whoopLatestSleepOnset)
        defaults.removeObject(forKey: Keys.whoopLatestWakeTime)
    }

    // MARK: - Oura

    var ouraConnected: Bool {
        get { defaults.bool(forKey: Keys.ouraConnected) }
        set { defaults.set(newValue, forKey: Keys.ouraConnected) }
    }

    var ouraRecommendedSleepHours: Double {
        get { defaults.double(forKey: Keys.ouraRecommendedSleepHours) }
        set { defaults.set(newValue, forKey: Keys.ouraRecommendedSleepHours) }
    }

    var ouraLastSyncDate: Date? {
        get { defaults.object(forKey: Keys.ouraLastSyncDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.ouraLastSyncDate) }
    }

    var ouraLatestSleepOnset: Date? {
        get { defaults.object(forKey: Keys.ouraLatestSleepOnset) as? Date }
        set { defaults.set(newValue, forKey: Keys.ouraLatestSleepOnset) }
    }

    var ouraLatestWakeTime: Date? {
        get { defaults.object(forKey: Keys.ouraLatestWakeTime) as? Date }
        set { defaults.set(newValue, forKey: Keys.ouraLatestWakeTime) }
    }

    func resetOuraData() {
        defaults.set(false, forKey: Keys.ouraConnected)
        defaults.set(0.0, forKey: Keys.ouraRecommendedSleepHours)
        defaults.removeObject(forKey: Keys.ouraLastSyncDate)
        defaults.removeObject(forKey: Keys.ouraLatestSleepOnset)
        defaults.removeObject(forKey: Keys.ouraLatestWakeTime)
    }
}
