import Foundation
import FirebaseAuth
import FirebaseFirestore

final class SleepHistoryStore {
    static let shared = SleepHistoryStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "lunifer_sleep_history"

    func recordNight(date: Date, duration: Double, onset: Date?, wake: Date?) {
        var entries = loadRawEntries()
        entries.append([
            "date": date.timeIntervalSince1970,
            "duration": duration,
            "onset": onset?.timeIntervalSince1970 ?? 0,
            "wake": wake?.timeIntervalSince1970 ?? 0
        ])

        if entries.count > 30 {
            entries = Array(entries.suffix(30))
        }
        defaults.set(entries, forKey: storageKey)

        guard let uid = Auth.auth().currentUser?.uid else { return }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let dateKey = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )

        var data: [String: Any] = [
            "date": date,
            "durationHours": duration
        ]
        if let onset { data["sleepOnset"] = onset }
        if let wake { data["wakeTime"] = wake }

        Firestore.firestore()
            .collection("users").document(uid)
            .collection("sleepHistory").document(dateKey)
            .setData(data) { error in
                if let error {
                    print("❌ Failed to save sleep night to Firestore: \(error.localizedDescription)")
                } else {
                    print("✅ Sleep night saved to Firestore (\(dateKey))")
                }
            }
    }

    func recentHistory(days: Int = 7) -> [SleepHistoryEntry] {
        let raw = loadRawEntries()
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let entries: [SleepHistoryEntry] = raw.compactMap { dict in
            guard let dateTS = dict["date"] as? Double,
                  let duration = dict["duration"] as? Double else {
                return nil
            }

            let date = Date(timeIntervalSince1970: dateTS)
            guard date >= cutoff else { return nil }

            let onsetTS = dict["onset"] as? Double ?? 0
            let wakeTS = dict["wake"] as? Double ?? 0

            return SleepHistoryEntry(
                date: date,
                durationHours: duration,
                sleepOnset: onsetTS > 0 ? Date(timeIntervalSince1970: onsetTS) : nil,
                wakeTime: wakeTS > 0 ? Date(timeIntervalSince1970: wakeTS) : nil
            )
        }

        return Array(entries.sorted { $0.date > $1.date }.prefix(days))
    }

    func averageDuration(days: Int = 7) -> Double? {
        let history = recentHistory(days: days)
        guard !history.isEmpty else { return nil }
        let total = history.reduce(0) { $0 + $1.durationHours }
        return total / Double(history.count)
    }

    func purgeBadEntries() {
        var entries = loadRawEntries()
        let before = entries.count
        entries = entries.filter { dict in
            guard let duration = dict["duration"] as? Double else { return false }
            return duration >= 3.0 && duration <= 12.0
        }

        if entries.count < before {
            defaults.set(entries, forKey: storageKey)
            print("🧹 Purged \(before - entries.count) corrupt sleep history entries")
        }
    }

    func clearLocalData() {
        defaults.removeObject(forKey: storageKey)
    }

    private func loadRawEntries() -> [[String: Any]] {
        defaults.array(forKey: storageKey) as? [[String: Any]] ?? []
    }
}
