import Foundation

final class AppPreferencesStore {
    static let shared = AppPreferencesStore()

    enum Keys {
        static let surveyCompleted = "surveyCompleted"

        // Onboarding walkthrough (one-time coach-mark dashboard/settings tour)
        static let hasSeenWalkthrough = "hasSeenWalkthrough"

        // Alarm
        static let mainAlarmSnoozeMinutes = "mainAlarmSnoozeMinutes"
        static let selectedAlarmSound = "selectedAlarmSound"
        static let luniferEnabled = "luniferEnabled"
        static let overrideActive = "overrideActive"
        static let overrideTimestamp = "overrideTimestamp"
        static let calculatedAlarmTimestamp = "calculatedAlarmTimestamp"

        // Added alarms (stored as a JSON-encoded [AddedAlarm] array)
        static let addedAlarms = "addedAlarms"

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

        // Wearable resolver
        static let hasWearable = "hasWearable"

        // Notifications
        static let batteryAlertEnabled    = "batteryAlertEnabled"
        static let wakeReminderEnabled    = "wakeReminderEnabled"
        static let commuteReminderEnabled = "commuteReminderEnabled"

        // Commute polling state (persisted for background task continuity)
        static let commuteArrivalTimestamp        = "commuteArrivalTimestamp"
        static let commutePreviousDurationMinutes = "commutePreviousDurationMinutes"
        static let commutePollingActive           = "commutePollingActive"

        // Rest-day event notification deduplication
        static let restDayNotificationSentDate = "lunifer_restday_notification_sent_date"

        // Rest-day alarm opt-in — set when the user taps "Yes" on the rest-day
        // early-event notification. Marks a specific rest day (start-of-day) on
        // which the user explicitly wants an alarm, so the rest-day cancel guards
        // leave that alarm in place instead of cancelling it.
        static let restDayAlarmOptInDate = "restDayAlarmOptInDate"

        // Feedback slowmode — timestamp of the last submitted feedback (one per day)
        static let lastFeedbackSubmittedDate = "lastFeedbackSubmittedDate"

        // Battery monitoring internals
        static let batteryDrainSamples = "lunifer_battery_drain_samples"
        static let batteryLastCheckTime = "lunifer_battery_last_check_time"
        static let batteryLastCheckLevel = "lunifer_battery_last_check_level"
        static let batteryLastWarnedAlarm = "lunifer_battery_last_warned_alarm"
    }

    private let defaults = UserDefaults.standard

    private init() {
        refreshHasWearable()
    }

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

    func resetAlarmOverride() {
        defaults.set(false, forKey: Keys.overrideActive)
        defaults.removeObject(forKey: Keys.overrideTimestamp)
    }

    // MARK: - Rest-day alarm opt-in

    /// The exact fire time of the alarm the user opted into on a rest day via the
    /// rest-day notification, or nil if there is no active opt-in. Stored as the
    /// full alarm time (not start-of-day) so the scheduling flow can tell whether
    /// an opted-in alarm is still pending vs. already fired / lapsed.
    var restDayAlarmOptInDate: Date? {
        get { defaults.object(forKey: Keys.restDayAlarmOptInDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.restDayAlarmOptInDate) }
    }

    /// True when the opted-in alarm's fire time falls on the same calendar day as
    /// `day`, so the rest-day cancel guards should NOT cancel that alarm.
    func hasRestDayAlarmOptIn(for day: Date) -> Bool {
        guard let optIn = restDayAlarmOptInDate else { return false }
        return Calendar.current.isDate(optIn, inSameDayAs: day)
    }

    /// The opted-in alarm's fire time if it is still in the future (hasn't fired or
    /// lapsed yet), else nil. Lets the scheduling flow preserve an opted-in rest-day
    /// alarm even after midnight, when "tomorrow" has rolled past the alarm's own day.
    func pendingRestDayAlarmDate() -> Date? {
        guard let optIn = restDayAlarmOptInDate, optIn > Date() else { return nil }
        return optIn
    }

    /// Records the exact fire time of the alarm the user opted into on a rest day.
    func setRestDayAlarmOptIn(for alarmDate: Date) {
        restDayAlarmOptInDate = alarmDate
    }

    /// Clears the rest-day alarm opt-in (e.g. once the alarm has fired, Lunifer is
    /// turned off, or the user signs out).
    func clearRestDayAlarmOptIn() {
        defaults.removeObject(forKey: Keys.restDayAlarmOptInDate)
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
        refreshHasWearable()
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
        refreshHasWearable()
    }

    // MARK: - Wearables

    var hasWearable: Bool {
        get { defaults.bool(forKey: Keys.hasWearable) }
        set { defaults.set(newValue, forKey: Keys.hasWearable) }
    }

    func refreshHasWearable() {
        let whoopAvailable = defaults.bool(forKey: Keys.whoopConnected)
            && defaults.double(forKey: Keys.whoopRecommendedSleepHours) > 0
        let ouraAvailable = defaults.bool(forKey: Keys.ouraConnected)
            && defaults.double(forKey: Keys.ouraRecommendedSleepHours) > 0

        hasWearable = whoopAvailable || ouraAvailable
    }
}
