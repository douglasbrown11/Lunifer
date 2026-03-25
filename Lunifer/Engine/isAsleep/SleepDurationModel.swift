import Foundation
import FirebaseFirestore
import FirebaseAuth

// ─────────────────────────────────────────────────────────────
// SleepDurationModel
// ─────────────────────────────────────────────────────────────
// Calculates the recommended sleep duration for a user based on
// age and survey data, then adapts over time using behavioral
// signals from SleepTracker and AlarmBehaviourLogger.
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
//
// The model starts with the midpoint of the recommended range
// for the user's age group, then adjusts based on:
//   1. Snooze frequency (more snoozes → needs more sleep)
//   2. Pre-alarm waking (waking before alarm → needs less sleep)
//   3. Actual measured sleep duration (from SleepTracker)

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

    /// Returns the recommended range (min, max) in hours for the user's age.
    static func rangeForAge(_ ageString: String) -> (min: Double, max: Double) {
        let age = Int(ageString) ?? 22

        switch age {
        case ...13:
            return (9.0, 11.0)
        case 14...17:
            return (8.0, 10.0)
        case 18...25:
            return (7.0, 9.0)
        case 26...64:
            return (7.0, 9.0)
        default:
            return (7.0, 8.0)
        }
    }

    // MARK: - Adaptive recommendation

    /// Calculates the current recommended sleep duration, starting from
    /// the age-based baseline and adjusting for behavioral signals.
    ///
    /// - Parameters:
    ///   - ageString: User's age from survey
    ///   - snoozeRate: Average snoozes per alarm over the last 7 days (0.0 – 5.0+)
    ///   - preAlarmWakeRate: Fraction of days the user woke before the alarm (0.0 – 1.0)
    ///   - avgActualDuration: Average actual sleep duration from SleepTracker (hours), nil if no data yet
    /// - Returns: Recommended sleep duration in hours
    static func recommendedDuration(
        ageString: String,
        snoozeRate: Double = 0,
        preAlarmWakeRate: Double = 0,
        avgActualDuration: Double? = nil
    ) -> Double {
        let baseline = baselineForAge(ageString)
        let range = rangeForAge(ageString)

        var adjustment: Double = 0

        // ── Snooze adjustment ────────────────────────────────
        // If the user snoozes a lot, they're not getting enough sleep.
        // Each average snooze per day shifts the recommendation up by 10 min.
        // Capped at +30 min so we don't recommend unrealistic amounts.
        //
        // snoozeRate 0   → +0 min
        // snoozeRate 1   → +10 min
        // snoozeRate 3+  → +30 min (capped)
        let snoozeAdjustment = min(snoozeRate * (10.0 / 60.0), 0.5)
        adjustment += snoozeAdjustment

        // ── Pre-alarm wake adjustment ────────────────────────
        // If the user regularly wakes before the alarm, they may
        // be sleeping more than they need, OR their body clock is
        // well-calibrated. We nudge the recommendation down slightly.
        //
        // preAlarmWakeRate 0.0 → no change
        // preAlarmWakeRate 0.5 → -7.5 min
        // preAlarmWakeRate 1.0 → -15 min
        let wakeAdjustment = preAlarmWakeRate * (-15.0 / 60.0)
        adjustment += wakeAdjustment

        // ── Actual duration convergence ──────────────────────
        // If we have measured sleep data, slowly converge toward
        // what the user actually sleeps — but only if it's within
        // the healthy range for their age.
        //
        // This gives a 20% pull toward actual behavior per update.
        // Over a week of data it will meaningfully shift the
        // recommendation toward reality.
        if let actual = avgActualDuration {
            let clampedActual = max(range.min, min(actual, range.max))
            let currentRecommendation = baseline + adjustment
            let convergence = (clampedActual - currentRecommendation) * 0.2
            adjustment += convergence
        }

        // Clamp to the healthy range for this age group
        let recommended = max(range.min, min(baseline + adjustment, range.max))

        return recommended
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
