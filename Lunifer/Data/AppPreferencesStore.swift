import Foundation

final class AppPreferencesStore {
    static let shared = AppPreferencesStore()

    enum Keys {
        static let surveyCompleted       = "surveyCompleted"
        // Alarm
        static let snoozeMinutes         = "snoozeMinutes"
        static let selectedAlarmSound    = "selectedAlarmSound"
        static let luniferEnabled        = "luniferEnabled"
        static let overrideActive        = "overrideActive"
        static let overrideTimestamp     = "overrideTimestamp"
        // Added alarm
        static let addedAlarmActive         = "addedAlarmActive"
        static let addedAlarmTimestamp      = "addedAlarmTimestamp"
        static let addedAlarmSound          = "addedAlarmSound"
        static let addedAlarmLabel          = "addedAlarmLabel"
        static let addedAlarmSnoozeMinutes  = "addedAlarmSnoozeMinutes"
        // Home location
        static let homeLatitude          = "homeLatitude"
        static let homeLongitude         = "homeLongitude"
        static let homeLocationSet       = "homeLocationSet"
        static let homeLocationName      = "homeLocationName"
        // Notifications
        static let batteryAlertEnabled   = "batteryAlertEnabled"
        static let wakeReminderEnabled   = "wakeReminderEnabled"
        // Battery monitoring internals
        static let batteryDrainSamples      = "lunifer_battery_drain_samples"
        static let batteryLastCheckTime     = "lunifer_battery_last_check_time"
        static let batteryLastCheckLevel    = "lunifer_battery_last_check_level"
        static let batteryLastWarnedAlarm   = "lunifer_battery_last_warned_alarm"
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
}
