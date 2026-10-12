import Foundation
import FirebaseAuth

@MainActor
final class SilentPushManager {
    static let shared = SilentPushManager()
    static let refreshMessageType = "lunifer_alarm_refresh"
    static let adaptiveSleepMessageType = "lunifer_adaptive_sleep_check"
    private static let baseURL = URL(string: "https://lunifer-whoop.dougiebrown516.workers.dev")!
    private init() {}

    func receivedDeviceToken(_ data: Data) async {
        let token = data.map { String(format: "%02x", $0) }.joined()
        KeychainHelper.save(token, forKey: KeychainHelper.Keys.apnsDeviceToken)
        await upload(token: token)
    }

    func syncStoredToken() async {
        guard let token = KeychainHelper.load(forKey: KeychainHelper.Keys.apnsDeviceToken) else { return }
        await upload(token: token)
    }

    func unregisterCurrentInstallation() async {
        guard storedInstallationID != nil else { return }
        try? await send(path: "/push/unregister", body: ["installationID": storedInstallationID!])
    }

    func refreshTomorrowAlarm(for refreshDate: String? = nil) async -> Bool {
        guard Auth.auth().currentUser != nil else { return false }
        let refreshDate = refreshDate ?? Self.localDayKey()
        guard Self.isLuniferEnabled else {
            await reportRefreshResult(localDate: refreshDate, status: "skipped", reason: "lunifer_disabled")
            return false
        }
        guard let answers = SurveyAnswersStore.shared.loadFromDefaults() else {
            await reportRefreshResult(localDate: refreshDate, status: "failed", reason: "missing_survey_answers")
            return false
        }
        guard let refreshed = await LuniferAlarm.shared.refreshTomorrowAlarm(
            answers: answers,
            preserveTodayPendingAlarm: false
        ) else {
            await reportRefreshResult(localDate: refreshDate, status: "failed", reason: "refresh_returned_nil")
            return false
        }
        let repairedAddedAlarms = await LuniferAlarm.shared.reconcileAddedAlarms()
        AppPreferencesStore.shared.finalizedMainAlarmDate = refreshed
        await syncStoredToken()
        await reportRefreshResult(
            localDate: refreshDate,
            status: "success",
            reason: repairedAddedAlarms > 0 ? "main_alarm_refreshed_added_repaired" : "main_alarm_refreshed",
            scheduledAlarmTime: refreshed
        )
        return Self.isLuniferEnabled || repairedAddedAlarms > 0
    }

    func handleTimeZoneChange() async -> Bool {
        guard Auth.auth().currentUser != nil,
              Self.isLuniferEnabled,
              let answers = SurveyAnswersStore.shared.loadFromDefaults() else { return false }
        guard let refreshed = await LuniferAlarm.shared.rescheduleMainAlarmForCurrentTimeZone(answers: answers) else {
            await syncStoredToken()
            return false
        }
        AppPreferencesStore.shared.finalizedMainAlarmDate = refreshed
        await syncStoredToken()
        return Self.isLuniferEnabled
    }

    func handleAdaptiveSleepCheck(for dayKey: String?) async -> Bool {
        guard Auth.auth().currentUser != nil,
              Self.isLuniferEnabled else { return false }
        let resolvedDayKey = dayKey ?? Self.localDayKey()
        guard !AppPreferencesStore.shared.adaptiveSleepPushCompleted(for: resolvedDayKey) else { return false }

        await SleepTracker.shared.runRetroactiveAnalysis()
        await LuniferAlarm.shared.performAdaptiveSleepProtectionCheck()

        if SleepTracker.shared.estimatedSleepOnset != nil {
            AppPreferencesStore.shared.markAdaptiveSleepPushCompleted(for: resolvedDayKey)
            await markAdaptiveSleepComplete(dayKey: resolvedDayKey)
        }
        return true
    }

    private static var isLuniferEnabled: Bool {
        UserDefaults.standard.object(forKey: AppPreferencesStore.Keys.luniferEnabled) as? Bool ?? true
    }

    static func clearStoredData() {
        KeychainHelper.delete(forKey: KeychainHelper.Keys.apnsDeviceToken)
        KeychainHelper.delete(forKey: KeychainHelper.Keys.pushInstallationID)
    }

    private var storedInstallationID: String? {
        KeychainHelper.load(forKey: KeychainHelper.Keys.pushInstallationID)
    }

    private func installationID() -> String {
        if let existing = storedInstallationID { return existing }
        let newID = UUID().uuidString.lowercased()
        KeychainHelper.save(newID, forKey: KeychainHelper.Keys.pushInstallationID)
        return newID
    }

    private func upload(token: String) async {
        guard Auth.auth().currentUser != nil else { return }
        var body = [
            "token": token,
            "installationID": installationID(),
            "timeZone": TimeZone.current.identifier,
            "environment": pushEnvironment
        ]
        if let bedtimeMinuteOfDay = Self.expectedBedtimeMinuteOfDay() {
            body["bedtimeMinuteOfDay"] = String(bedtimeMinuteOfDay)
        }
        try? await send(path: "/push/register", body: body)
    }

    private func markAdaptiveSleepComplete(dayKey: String) async {
        try? await send(path: "/push/adaptive-complete", body: [
            "installationID": installationID(),
            "dayKey": dayKey
        ])
    }

    private func reportRefreshResult(
        localDate: String,
        status: String,
        reason: String,
        scheduledAlarmTime: Date? = nil
    ) async {
        var body = [
            "installationID": installationID(),
            "localDate": localDate,
            "status": status,
            "reason": reason
        ]
        if let scheduledAlarmTime {
            body["scheduledAlarmTime"] = ISO8601DateFormatter().string(from: scheduledAlarmTime)
        }
        try? await send(path: "/push/refresh-result", body: body)
    }

    private var pushEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    private func send(path: String, body: [String: String]) async throws {
        guard let user = Auth.auth().currentUser else { return }
        let idToken = try await user.getIDToken()
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private static func expectedBedtimeMinuteOfDay() -> Int? {
        guard let answers = SurveyAnswersStore.shared.loadFromDefaults() else { return nil }
        let wakeDate: Date?
        if let scheduled = LuniferAlarm.shared.scheduledWakeTime {
            wakeDate = scheduled
        } else if let finalized = AppPreferencesStore.shared.finalizedMainAlarmDate {
            wakeDate = finalized
        } else {
            let timestamp = UserDefaults.standard.double(forKey: AppPreferencesStore.Keys.calculatedAlarmTimestamp)
            wakeDate = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        }
        guard let wakeDate else { return nil }
        let sleepHours = WearableRecommendationStore.recommendedHours(
            from: WearableRecommendationStore.currentSources(),
            fallback: answers
        )
        let bedtime = wakeDate.addingTimeInterval(-sleepHours * 3600)
        let components = Calendar.current.dateComponents([.hour, .minute], from: bedtime)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        return hour * 60 + minute
    }

    private static func localDayKey(for date: Date = Date()) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
