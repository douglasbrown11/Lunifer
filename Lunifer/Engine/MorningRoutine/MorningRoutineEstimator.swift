import Foundation
import Combine
import CoreMotion

// ─────────────────────────────────────────────────────────────
// MorningRoutineEstimator
// ─────────────────────────────────────────────────────────────
// Passively estimates how long a user's morning routine actually
// takes — the gap between waking up and physically leaving — and
// surfaces a recommendation when their manually-entered routine
// time is meaningfully off.
//
// SCOPE (intentionally narrow):
//   • Runs ONLY for "student" or "commuter" lifestyles. These are
//     the only users with an observable end-of-routine event
//     (departure), so they're the only ones we can measure.
//     `configure(for:)` flips the estimator on/off whenever the
//     lifestyle changes (e.g. in About You settings).
//   • Samples are collected ONLY on the user's wake days — the days
//     they've asked Lunifer to wake them. Non-wake-day mornings are
//     ignored entirely.
//
// HOW IT MEASURES:
//   routine = departureTime − wakeTime
//     wakeTime      — supplied by the caller (SleepTracker wake
//                     detection, or the alarm "Stop" tap).
//     departureTime — first sustained commute-type motion after
//                     wake, found by querying CoreMotion's historical
//                     activity buffer (same technique SleepTracker
//                     uses for retroactive sleep analysis). Because
//                     the scan is retroactive, departure is still
//                     captured even if the app was suspended while
//                     the user left the house.
//
// RECOMMENDATION RULE:
//   • Needs at least `requiredSamples` (12) valid wake-day samples.
//   • Uses the MEDIAN of the most recent `rollingWindow` (20) samples
//     — median is robust to spiky mornings (gym day, slow start).
//   • Only recommends when |median − manualRoutine| > 10 minutes.
//   • After a user dismisses a suggestion, a cooldown suppresses the
//     same suggestion for `dismissalCooldownDays`.
//
// The estimator NEVER overwrites the user's manual value on its own.
// It only produces a `RoutineRecommendation`; the UI decides whether
// to show it and the user taps to accept.
//
// ── Wiring (call sites, handled separately) ───────────────────
//   • `configure(for:)`  → dashboard load + About You lifestyle change
//   • `handleWakeDetected(at:answers:)` → SleepTracker wake / alarm Stop
//   • `refresh(answers:)` → app-becomes-active + sleep background task
//   • `recommendation(currentRoutineMinutes:)` → dashboard / settings UI
//   • `clearLocalData()` → AccountDataManager sign-out / delete
// ─────────────────────────────────────────────────────────────

@MainActor
final class MorningRoutineEstimator: ObservableObject {

    static let shared = MorningRoutineEstimator()

    // ── Tunables ──────────────────────────────────────────────

    /// Minimum number of valid wake-day samples before any recommendation.
    private let requiredSamples = 12

    /// Only the most recent N samples feed the median, so the estimate
    /// keeps adapting if the user's mornings genuinely change over time.
    private let rollingWindow = 20

    /// Reject samples outside this band as implausible (sensor noise,
    /// a forgotten-something round trip, a missed departure, etc.).
    private let minValidMinutes = 5
    private let maxValidMinutes = 180

    /// A recommendation is only surfaced when the observed median differs
    /// from the manual routine by strictly more than this many minutes.
    private let recommendationThresholdMinutes = 10

    /// The qualifying departure motion must persist at least this long to
    /// count — filters out brief in-house movement (walking to the kitchen).
    private let departureSustainMinutes: Double = 3

    /// After a user dismisses a suggestion, don't re-offer the same value
    /// for this many days.
    private let dismissalCooldownDays = 7

    // ── Published state ───────────────────────────────────────

    @Published private(set) var isEnabled = false
    @Published private(set) var sampleCount = 0

    // ── Internals ─────────────────────────────────────────────

    private let motionManager = CMMotionActivityManager()
    private let defaults = UserDefaults.standard

    // NOTE: keys are kept local to this file for now. They should be
    // centralised in AppPreferencesStore.Keys and cleared by
    // AccountDataManager when this feature is wired in (see header).
    private let samplesKey         = "lunifer_routine_samples"
    private let armedWakeKey       = "lunifer_routine_armed_wake"
    private let armedDayKey        = "lunifer_routine_armed_day"
    private let lastRecordedDayKey = "lunifer_routine_last_recorded_day"
    private let dismissedDateKey   = "lunifer_routine_rec_dismissed_at"
    private let dismissedValueKey  = "lunifer_routine_rec_dismissed_value"

    private init() {
        sampleCount = loadSamples().count
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Enable / disable (lifestyle gating)
    // ─────────────────────────────────────────────────────────

    /// Turns estimation on for commuters/students and off for everyone
    /// else. Call on dashboard load and whenever the lifestyle changes
    /// in settings so the feature switches with the user's preference.
    func configure(for answers: SurveyAnswers) {
        setEnabled(answers.lifestyle == "student" || answers.lifestyle == "commuter")
    }

    func setEnabled(_ enabled: Bool) {
        if isEnabled == enabled { return }
        isEnabled = enabled
        if !enabled {
            // Stop collecting and drop any in-flight session. Historical
            // samples are preserved so switching back resumes cleanly,
            // but they're never surfaced while disabled.
            motionManager.stopActivityUpdates()
            clearArmedSession()
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Signal intake
    // ─────────────────────────────────────────────────────────

    /// Arms a measurement session for the morning. Call when a wake is
    /// detected. No-ops unless the feature is enabled and `wakeTime`
    /// falls on one of the user's wake days. One session per calendar day.
    func handleWakeDetected(at wakeTime: Date, answers: SurveyAnswers) {
        // Re-resolve enablement from the latest answers so collection works even
        // on a cold background relaunch where configure(for:) hasn't run from UI.
        configure(for: answers)
        guard isEnabled else { return }
        guard isWakeDay(wakeTime, answers: answers) else { return }

        let dayKey = Self.dayKey(for: wakeTime)
        if defaults.string(forKey: lastRecordedDayKey) == dayKey { return } // already done today

        defaults.set(wakeTime.timeIntervalSince1970, forKey: armedWakeKey)
        defaults.set(dayKey, forKey: armedDayKey)

        // Departure may already have happened (e.g. retroactive wake
        // detection after the user is long gone) — try immediately.
        Task { await scanForDeparture(commuteMode: answers.commuteMode) }
    }

    /// Re-attempts departure detection for an armed session. Call when the
    /// app returns to the foreground and from the sleep background task, so
    /// a departure that happened while suspended is still captured.
    func refresh(answers: SurveyAnswers) {
        configure(for: answers)
        guard isEnabled else { return }
        Task { await scanForDeparture(commuteMode: answers.commuteMode) }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Departure detection
    // ─────────────────────────────────────────────────────────

    private func scanForDeparture(commuteMode: String) async {
        guard CMMotionActivityManager.isActivityAvailable() else { return }

        let wakeTS = defaults.double(forKey: armedWakeKey)
        guard wakeTS > 0 else { return }                       // no armed session
        let wakeTime = Date(timeIntervalSince1970: wakeTS)
        let dayKey   = defaults.string(forKey: armedDayKey) ?? Self.dayKey(for: wakeTime)

        if defaults.string(forKey: lastRecordedDayKey) == dayKey {
            clearArmedSession()
            return
        }

        let now = Date()
        let activities = await queryMotionHistory(from: wakeTime, to: now)

        if let departure = firstSustainedDeparture(in: activities, mode: commuteMode, after: wakeTime) {
            let minutes = Int(departure.timeIntervalSince(wakeTime) / 60.0)
            if minutes >= minValidMinutes && minutes <= maxValidMinutes {
                recordSample(MorningRoutineSample(
                    date: Calendar.current.startOfDay(for: wakeTime),
                    wakeTime: wakeTime,
                    departureTime: departure
                ))
            }
            // Either way the session for today is resolved.
            defaults.set(dayKey, forKey: lastRecordedDayKey)
            clearArmedSession()
            return
        }

        // No departure yet. If too much time has elapsed since wake, give up
        // for the day so we don't keep scanning or record a garbage duration.
        if now.timeIntervalSince(wakeTime) > Double(maxValidMinutes) * 60 {
            defaults.set(dayKey, forKey: lastRecordedDayKey)
            clearArmedSession()
        }
    }

    /// Queries CoreMotion's historical activity buffer between two dates.
    private func queryMotionHistory(from start: Date, to end: Date) async -> [CMMotionActivity] {
        await withCheckedContinuation { continuation in
            motionManager.queryActivityStarting(from: start, to: end, to: .main) { activities, _ in
                continuation.resume(returning: activities ?? [])
            }
        }
    }

    /// Returns the start time of the first commute-type movement after wake
    /// that persists for at least `departureSustainMinutes` — i.e. the user
    /// actually leaving, not just moving around inside.
    private func firstSustainedDeparture(
        in activities: [CMMotionActivity],
        mode: String,
        after wakeTime: Date
    ) -> Date? {
        let sorted = activities
            .filter { $0.startDate >= wakeTime }
            .sorted { $0.startDate < $1.startDate }

        for (index, activity) in sorted.enumerated() {
            guard isCommuteMovement(activity, mode: mode) else { continue }

            // Confirm the movement holds across the sustain window; a
            // confident return to stationary inside it marks a false blip.
            let windowEnd = activity.startDate.addingTimeInterval(departureSustainMinutes * 60)
            var sustained = true
            for next in sorted[index...] {
                if next.startDate > windowEnd { break }
                if next.stationary && isConfident(next) {
                    sustained = false
                    break
                }
            }
            if sustained { return activity.startDate }
        }
        return nil
    }

    /// Maps the user's commute mode to the motion activities that indicate
    /// they've left. Requires medium-or-higher confidence to reduce noise.
    private func isCommuteMovement(_ activity: CMMotionActivity, mode: String) -> Bool {
        guard isConfident(activity) else { return false }
        switch mode {
        case "drive":   return activity.automotive
        case "transit": return activity.automotive || activity.walking
        case "walk":    return activity.walking || activity.running
        case "bike":    return activity.cycling || activity.walking
        default:        return activity.automotive || activity.cycling || activity.walking
        }
    }

    private func isConfident(_ activity: CMMotionActivity) -> Bool {
        activity.confidence.rawValue >= CMMotionActivityConfidence.medium.rawValue
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Recommendation
    // ─────────────────────────────────────────────────────────

    /// Returns a recommendation when enough clean samples exist and the
    /// observed median is more than `recommendationThresholdMinutes` away
    /// from the user's current manual routine. Returns nil otherwise, or
    /// while a dismissed value is still within its cooldown.
    func recommendation(currentRoutineMinutes: Int) -> RoutineRecommendation? {
        guard isEnabled else { return nil }

        let samples = recentSamples()
        guard samples.count >= requiredSamples else { return nil }

        let median = medianMinutes(of: samples)
        guard abs(median - currentRoutineMinutes) > recommendationThresholdMinutes else { return nil }

        // Respect a recent dismissal of the same suggested value.
        if let dismissedAt = defaults.object(forKey: dismissedDateKey) as? Date {
            let dismissedValue = defaults.integer(forKey: dismissedValueKey)
            let daysSince = Calendar.current.dateComponents([.day], from: dismissedAt, to: Date()).day ?? .max
            if dismissedValue == median && daysSince < dismissalCooldownDays { return nil }
        }

        return RoutineRecommendation(
            suggestedMinutes: median,
            currentMinutes: currentRoutineMinutes,
            sampleCount: samples.count
        )
    }

    /// Record that the user declined a suggestion so it isn't re-shown
    /// immediately. Call from the UI when a recommendation is dismissed.
    func dismissRecommendation(suggestedMinutes: Int) {
        defaults.set(Date(), forKey: dismissedDateKey)
        defaults.set(suggestedMinutes, forKey: dismissedValueKey)
    }

    /// Clears the dismissal cooldown — call when the user accepts a
    /// suggestion (the UI writes the new value into `answers.routine`).
    func acknowledgeAcceptedRecommendation() {
        defaults.removeObject(forKey: dismissedDateKey)
        defaults.removeObject(forKey: dismissedValueKey)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Sample storage
    // ─────────────────────────────────────────────────────────

    private func recordSample(_ sample: MorningRoutineSample) {
        var samples = loadSamples().filter {
            Self.dayKey(for: $0.date) != Self.dayKey(for: sample.date)   // one per day
        }
        samples.append(sample)
        samples.sort { $0.date < $1.date }
        if samples.count > rollingWindow {
            samples = Array(samples.suffix(rollingWindow))
        }
        saveSamples(samples)
        sampleCount = samples.count
    }

    private func recentSamples() -> [MorningRoutineSample] {
        Array(loadSamples().sorted { $0.date < $1.date }.suffix(rollingWindow))
    }

    private func medianMinutes(of samples: [MorningRoutineSample]) -> Int {
        let minutes = samples.map(\.durationMinutes).sorted()
        guard !minutes.isEmpty else { return 0 }
        let count = minutes.count
        if count % 2 == 1 { return minutes[count / 2] }
        return Int((Double(minutes[count / 2 - 1] + minutes[count / 2]) / 2.0).rounded())
    }

    private func loadSamples() -> [MorningRoutineSample] {
        guard let data = defaults.data(forKey: samplesKey),
              let samples = try? JSONDecoder().decode([MorningRoutineSample].self, from: data)
        else { return [] }
        return samples
    }

    private func saveSamples(_ samples: [MorningRoutineSample]) {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        defaults.set(data, forKey: samplesKey)
    }

    /// Clears all stored samples and session state. Call on sign-out /
    /// account deletion so routine data does not leak between accounts.
    func clearLocalData() {
        Self.clearStoredData()
        sampleCount = 0
    }

    /// Nonisolated wipe of all persisted keys, callable from non-MainActor
    /// cleanup (e.g. `AccountDataManager`). Mirrors the instance key list above.
    nonisolated static func clearStoredData() {
        let defaults = UserDefaults.standard
        for key in ["lunifer_routine_samples",
                    "lunifer_routine_armed_wake",
                    "lunifer_routine_armed_day",
                    "lunifer_routine_last_recorded_day",
                    "lunifer_routine_rec_dismissed_at",
                    "lunifer_routine_rec_dismissed_value"] {
            defaults.removeObject(forKey: key)
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: - Helpers
    // ─────────────────────────────────────────────────────────

    private func clearArmedSession() {
        defaults.removeObject(forKey: armedWakeKey)
        defaults.removeObject(forKey: armedDayKey)
    }

    /// True when `date` falls on one of the user's configured wake days.
    private func isWakeDay(_ date: Date, answers: SurveyAnswers) -> Bool {
        let ids = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        let id = ids[Calendar.current.component(.weekday, from: date) - 1]
        return answers.wakeDays.contains(id)
    }

    private static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// ─────────────────────────────────────────────────────────────
// Supporting types
// ─────────────────────────────────────────────────────────────

/// A single measured morning: how long it took from waking to leaving.
struct MorningRoutineSample: Codable {
    let date: Date            // start of the wake day this sample belongs to
    let wakeTime: Date
    let departureTime: Date

    var durationMinutes: Int {
        max(0, Int(departureTime.timeIntervalSince(wakeTime) / 60.0))
    }
}

/// A suggestion to update the manual routine duration toward the observed median.
struct RoutineRecommendation {
    let suggestedMinutes: Int
    let currentMinutes: Int
    let sampleCount: Int

    /// Positive = mornings are taking longer than the manual value.
    var deltaMinutes: Int { suggestedMinutes - currentMinutes }
}
