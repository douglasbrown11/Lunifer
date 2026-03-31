import Foundation

// ─────────────────────────────────────────────────────────────
// SleepHistoryMock
// ─────────────────────────────────────────────────────────────
// Static mock data for SwiftUI previews and local testing.
// Use SleepHistoryMock.entries to populate SleepHistoryChart
// without requiring real UserDefaults / Firestore data.
//
// Usage in a preview:
//   SleepHistoryChart(
//       entries: SleepHistoryMock.entries,
//       recommendedHours: 8.0
//   )
//
// To seed the local store during a debug build:
//   SleepHistoryMock.seedStore()

struct SleepHistoryMock {

    // MARK: - Static entries (last 7 nights, oldest first)

    /// Seven nights of realistic-looking sleep data ending today.
    static var entries: [SleepHistoryEntry] {
        let cal  = Calendar.current
        let now  = Date()

        // (daysAgo, sleepHours, bedtimeHour, bedtimeMin)
        let nights: [(Int, Double, Int, Int)] = [
            (6, 6.5,  23, 10),   // 6 nights ago — short night
            (5, 7.75, 22, 45),   // 5 nights ago — decent
            (4, 8.25, 23,  0),   // 4 nights ago — above goal
            (3, 5.25,  0, 30),   // 3 nights ago — late night, short
            (2, 9.0,  22, 15),   // 2 nights ago — great night
            (1, 7.5,  23, 20),   // yesterday    — on target
            (0, 8.5,  22, 50),   // today        — above goal
        ]

        return nights.compactMap { (daysAgo, hours, bedH, bedM) in
            guard let wakeDate = cal.date(
                byAdding: .day,
                value: -daysAgo,
                to: cal.startOfDay(for: now)
            ) else { return nil }

            // Approximate bedtime the night before the wake date
            let bedtimeBase = cal.date(byAdding: .day, value: -1, to: wakeDate) ?? wakeDate
            var comps = cal.dateComponents([.year, .month, .day], from: bedtimeBase)
            comps.hour   = bedH
            comps.minute = bedM
            let onset = cal.date(from: comps)

            return SleepHistoryEntry(
                date:          wakeDate,
                durationHours: hours,
                sleepOnset:    onset,
                wakeTime:      onset.map { $0.addingTimeInterval(hours * 3600) }
            )
        }
    }

    // MARK: - Store seeding (debug only)

#if DEBUG
    /// Writes mock entries into the live SleepHistoryStore so the full
    /// app UI (not just previews) shows realistic chart data.
    /// Call once from a debug menu or app launch flag.
    static func seedStore() {
        let store = SleepHistoryStore.shared
        for entry in entries {
            store.recordNight(
                date:     entry.date,
                duration: entry.durationHours,
                onset:    entry.sleepOnset,
                wake:     entry.wakeTime
            )
        }
        print("🌙 SleepHistoryMock: seeded \(entries.count) nights into SleepHistoryStore")
    }
#endif
}
