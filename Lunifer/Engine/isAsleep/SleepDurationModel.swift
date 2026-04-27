import Foundation

// ─────────────────────────────────────────────────────────────
// SleepDurationModel
// ─────────────────────────────────────────────────────────────
// Calculates age-based baseline sleep duration values and formats
// durations for display.
//
// DATA SOURCES:
//   - National Sleep Foundation guidelines (2021)
//   - CDC recommended sleep durations
//   - American Academy of Sleep Medicine consensus
//
// AGE-BASED RECOMMENDATIONS (from research):
//   Teens     (14–17):  8.0 – 10.0 hours
//   Young     (18–25):  7.0 –  9.0 hours
//   Adults    (26–64):  7.0 –  9.0 hours
//   Older     (65+):    7.0 –  8.0 hours

struct SleepDurationModel {

    // MARK: - Age-based baseline

    /// Returns the recommended sleep duration in hours based on age.
    /// Uses the midpoint of the National Sleep Foundation range.
    ///
    /// - Parameter ageString: The user's age as a string (from SurveyAnswers.age)
    /// - Returns: Recommended hours of sleep (e.g. 8.5)
    static func baselineForAge(_ ageString: String) -> Double {
        let age = Int(ageString) ?? 22  // default to young adult if unparseable

        switch age {
        case ...13:
            // Children — shouldn't normally be using Lunifer,
            // but return a safe value (midpoint of 9–11)
            return 10.0
        case 14...17:
            // Teenagers: 8–10 hours recommended
            // Midpoint: 9.0
            return 9.0
        case 18...25:
            // Young adults: 7–9 hours recommended
            // Midpoint: 8.0
            return 8.0
        case 26...64:
            // Adults: 7–9 hours recommended
            // Midpoint: 8.0
            return 8.0
        default:
            // Older adults (65+): 7–8 hours recommended
            // Midpoint: 7.5
            return 7.5
        }
    }

    // MARK: - Formatting

    /// Formats a duration in hours to a display string like "8h 15m".
    static func formatted(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        if m == 0 {
            return "\(h) hours"
        }
        return "\(h) hours \(m)m"
    }

    /// Formats a duration in hours to a short display like "8:15".
    static func shortFormatted(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%d:%02d", h, m)
    }
}

// ─────────────────────────────────────────────────────────────
// SleepHistoryEntry
// ─────────────────────────────────────────────────────────────
// A single night's sleep data, used for the 7-day history chart.

struct SleepHistoryEntry: Identifiable {
    let id = UUID()
    let date: Date
    let durationHours: Double
    let sleepOnset: Date?
    let wakeTime: Date?

    /// Day-of-week abbreviation for chart labels (e.g. "Mon", "Tue").
    var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    /// Formatted duration for display (e.g. "7h 32m").
    var formattedDuration: String {
        SleepDurationModel.formatted(durationHours)
    }
}

// ─────────────────────────────────────────────────────────────
// SleepHistoryManager
// ─────────────────────────────────────────────────────────────
// Persists and retrieves sleep history from UserDefaults.
// Keeps the last 30 nights of data.

final class SleepHistoryManager {

    static let shared = SleepHistoryManager()
    private let store = SleepHistoryStore.shared

    /// Records a completed night of sleep locally and syncs to Firestore.
    func recordNight(date: Date, duration: Double, onset: Date?, wake: Date?) {
        store.recordNight(date: date, duration: duration, onset: onset, wake: wake)
    }

    /// Returns sleep history entries from the last `days` calendar days, most recent first.
    /// Filters by actual date rather than entry count, so stale development entries
    /// don't corrupt the average once real data starts accumulating.
    func recentHistory(days: Int = 7) -> [SleepHistoryEntry] {
        store.recentHistory(days: days)
    }

    /// Average sleep duration over the last N nights. Nil if no data.
    func averageDuration(days: Int = 7) -> Double? {
        store.averageDuration(days: days)
    }

    /// Removes entries whose duration is outside the realistic 3–12 hour band.
    /// Call once at app launch to clear any corrupt data written during development.
    func purgeBadEntries() {
        store.purgeBadEntries()
    }
}
