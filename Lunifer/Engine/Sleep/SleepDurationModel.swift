import Foundation

// ─────────────────────────────────────────────────────────────
// SleepDurationModel
// ─────────────────────────────────────────────────────────────
// Calculates age-based baseline sleep duration values and formats
// durations for display.
//

//
// AGE-BASED RECOMMENDATIONS (from research):
//   Children and teens (0–17): 8.0 – 10.0 hours
//   Young     (18–25):  7.0 –  9.0 hours
//   Adults    (26–64):  7.0 –  9.0 hours
//   Older     (65+):    7.0 –  8.0 hours

struct SleepDurationModel {

    // MARK: - Age-based baseline

    /// Returns the recommended sleep duration in hours based on age.
    /// Uses the midpoint of the National Sleep Foundation range.
    ///
    /// - Parameter ageString: The user's birthday as "yyyy-MM-dd" (from SurveyAnswers.age),
    ///   or a plain age integer string for legacy data.
    /// - Returns: Recommended hours of sleep (e.g. 8.5)
    static func baselineForAge(_ ageString: String) -> Double {
        let age: Int
        let birthdayFormatter = DateFormatter()
        birthdayFormatter.dateFormat = "yyyy-MM-dd"
        if let birthday = birthdayFormatter.date(from: ageString) {
            age = Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 22
        } else {
            // Legacy fallback: plain integer age string ("18", "22", etc.)
            age = Int(ageString) ?? 22
        }

        switch age {
        case ...17:
            // Children and teenagers: 8–10 hours recommended
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
            return "\(h) hrs"
        }
        return "\(h) hrs \(m)m"
    }

    /// Formats a duration in hours to a short display like "8:15".
    static func shortFormatted(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%d:%02d", h, m)
    }
}
