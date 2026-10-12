import Foundation

// ─────────────────────────────────────────────────────────────
// SleepDurationModel
// ─────────────────────────────────────────────────────────────
// Calculates baseline sleep duration values and formats durations for display.

struct SleepDurationModel {

    // MARK: - Baseline

    /// Returns Lunifer's default sleep duration when no wearable or manual
    /// preference is available.
    static func defaultBaselineHours() -> Double {
        8.0
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
