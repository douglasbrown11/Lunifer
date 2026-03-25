import Foundation

final class SleepTrackingStore {
    static let shared = SleepTrackingStore()

    private let defaults = UserDefaults.standard

    private let lastInteractionKey = "lunifer_last_interaction"
    private let interactionLogKey = "lunifer_interaction_log"
    private let historicalKey = "lunifer_avg_sleep_onset"
    private let sleepLogKey = "lunifer_sleep_log"
    private let lastRetroactiveAnalysisKey = "lunifer_last_retroactive_analysis"

    func recordInteraction(at date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: lastInteractionKey)

        var log = loadInteractionLog()
        log.append(date)

        let cutoff = date.addingTimeInterval(-24 * 3600)
        log.removeAll { $0 < cutoff }
        saveInteractionLog(log)
    }

    func lastInteractionDate() -> Date? {
        let timestamp = defaults.double(forKey: lastInteractionKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    func loadInteractionLog() -> [Date] {
        let timestamps = defaults.array(forKey: interactionLogKey) as? [Double] ?? []
        return timestamps.map { Date(timeIntervalSince1970: $0) }
    }

    func saveInteractionLog(_ log: [Date]) {
        defaults.set(log.map(\.timeIntervalSince1970), forKey: interactionLogKey)
    }

    func historicalAverageSleepOnset() -> Double? {
        let stored = defaults.double(forKey: historicalKey)
        return stored > 0 ? stored : nil
    }

    func setHistoricalAverageSleepOnset(_ value: Double?) {
        defaults.set(value ?? 0, forKey: historicalKey)
    }

    func lastRetroactiveAnalysisDate() -> Date? {
        let timestamp = defaults.double(forKey: lastRetroactiveAnalysisKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    func setLastRetroactiveAnalysisDate(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: lastRetroactiveAnalysisKey)
    }

    func appendSleepEvent(type: String, at date: Date) {
        var log = defaults.array(forKey: sleepLogKey) as? [[String: Any]] ?? []
        log.append([
            "type": type,
            "timestamp": date.timeIntervalSince1970,
            "dayOfWeek": Calendar.current.component(.weekday, from: date)
        ])
        if log.count > 180 {
            log = Array(log.suffix(180))
        }
        defaults.set(log, forKey: sleepLogKey)
    }

    func clearLocalData() {
        for key in [
            lastInteractionKey,
            interactionLogKey,
            historicalKey,
            sleepLogKey,
            lastRetroactiveAnalysisKey
        ] {
            defaults.removeObject(forKey: key)
        }
    }
}
