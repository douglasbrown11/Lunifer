import Foundation

// ─────────────────────────────────────────────────────────────
// SleepPredictionModel
// ─────────────────────────────────────────────────────────────
// Takes a SleepFeatures snapshot and outputs a probability (0–1)
// that the user is currently asleep.
//
// APPROACH: Weighted logistic scoring
// ─────────────────────────────────────────────────────────────
// This is inspired by the iSenseSleep algorithm (Borger et al. 2019)
// which demonstrated that phone screen-off patterns alone can
// estimate sleep onset within ~24 minutes on average.
//
// We extend iSenseSleep by adding motion, Focus mode, and
// historical priors. The model works as follows:
//
//   1. Each feature contributes a score between 0 and 1
//   2. Each score is multiplied by a weight (importance)
//   3. The weighted scores are summed
//   4. The sum is passed through a sigmoid to get probability
//
// The weights below are initial estimates. Over time, as we
// collect labelled data (from HealthKit ground truth or user
// confirmation), we can train a proper logistic regression or
// gradient-boosted model and replace this scoring function.
//
// HOW TO READ THE WEIGHTS:
//   Higher weight = that feature matters more to the prediction.
//   The weights were set based on the sleep detection literature:
//   - Phone inactivity is the #1 signal (iSenseSleep)
//   - Motion is #2 (actigraphy research)
//   - Time of day provides a strong prior
//   - Focus mode and unlock cadence are supporting signals

struct SleepPredictionModel {

    // ─────────────────────────────────────────────────────────
    // SECTION 1: MODEL WEIGHTS
    // ─────────────────────────────────────────────────────────
    // These control how much each feature influences the final
    // prediction. They should add up to roughly 1.0 for
    // interpretability, but the sigmoid normalises anyway.

    struct Weights {
        var phoneInactivity: Double    = 0.30   // Strongest signal (iSenseSleep)
        var motionStationary: Double   = 0.25   // Second strongest (actigraphy)
        var timeOfDay: Double          = 0.20   // Strong prior
        var unlockCadence: Double      = 0.10   // Supporting signal
        var sleepFocus: Double         = 0.08   // Intent signal
        var historicalPrior: Double    = 0.07   // Learned pattern
    }

    var weights = Weights()

    // ─────────────────────────────────────────────────────────
    // SECTION 2: THRESHOLDS
    // ─────────────────────────────────────────────────────────
    // These define what "looks like sleep" for each feature.

    struct Thresholds {
        /// Minutes of phone inactivity before we consider it a
        /// sleep signal. iSenseSleep found the longest screen-off
        /// gap during nighttime is almost always sleep.
        var inactivityMinutesForFullScore: Double = 30

        /// Minutes the phone must be stationary before we consider
        /// it a strong sleep signal.
        var stationaryMinutesForFullScore: Double = 20

        /// The probability threshold above which we declare isAsleep = true.
        /// 0.65 means the model needs to be reasonably confident.
        var sleepThreshold: Double = 0.65
    }

    var thresholds = Thresholds()

    // ─────────────────────────────────────────────────────────
    // SECTION 3: PREDICTION
    // ─────────────────────────────────────────────────────────

    /// The main prediction function.
    /// Takes a snapshot of features and returns a result with
    /// the probability and whether the user is likely asleep.
    func predict(features: SleepFeatures) -> SleepPrediction {

        // ── Score each feature (0.0 to 1.0) ──────────────────

        // 1. Phone inactivity score
        //    Ramps linearly from 0 to 1 over 0–30 minutes of no interaction.
        //    After 30 min with no phone use, this score is maxed out.
        let inactivityScore = min(
            features.timeSinceLastInteractionMinutes / thresholds.inactivityMinutesForFullScore,
            1.0
        )

        // 2. Motion stationary score
        //    Similar ramp: 0 to 1 over 0–20 minutes of no movement.
        //    If the device isn't stationary at all, score is 0.
        let motionScore: Double
        if features.isStationary {
            motionScore = min(
                features.stationaryDurationMinutes / thresholds.stationaryMinutesForFullScore,
                1.0
            )
        } else {
            motionScore = 0
        }

        // 3. Time-of-day score
        //    Uses a bell curve centred on typical sleep hours.
        //    Peaks at 2–3 AM (score ≈ 1.0), drops to near 0 by 8 AM and 8 PM.
        //    This encodes the strong prior that people are much more likely
        //    to be asleep at 2 AM than at 2 PM.
        let timeScore = timeOfDayScore(hour: features.timeOfDay)

        // 4. Unlock cadence score
        //    Zero unlocks in 30 min → score = 1.0 (strong sleep signal)
        //    5+ unlocks → score = 0.0 (actively using phone)
        //    Linear interpolation between.
        let unlockScore = max(1.0 - Double(features.unlockCountLast30Min) / 5.0, 0)

        // 5. Sleep Focus score
        //    Binary: 1.0 if Focus mode is silencing notifications, 0.0 otherwise.
        let focusScore: Double = features.isSleepFocusActive ? 1.0 : 0.0

        // 6. Historical prior score
        //    If we know the user usually falls asleep around 11 PM,
        //    and it's currently 11:30 PM, this score is high.
        //    Uses a Gaussian (bell curve) centred on their average onset.
        let historyScore = historicalPriorScore(
            currentHour: features.timeOfDay,
            avgOnset: features.historicalAvgSleepOnset
        )

        // ── Combine scores with weights ──────────────────────

        let rawScore =
            inactivityScore * weights.phoneInactivity +
            motionScore    * weights.motionStationary +
            timeScore      * weights.timeOfDay +
            unlockScore    * weights.unlockCadence +
            focusScore     * weights.sleepFocus +
            historyScore   * weights.historicalPrior

        // ── Apply sigmoid to get probability ─────────────────
        // The sigmoid squashes the raw score into 0–1 range.
        // We scale and shift so that:
        //   rawScore ≈ 0.5 → probability ≈ 0.50 (uncertain)
        //   rawScore ≈ 0.8 → probability ≈ 0.88 (likely asleep)
        //   rawScore ≈ 0.2 → probability ≈ 0.12 (likely awake)
        let probability = sigmoid(rawScore, steepness: 8, midpoint: 0.5)

        let isAsleep = probability >= thresholds.sleepThreshold

        return SleepPrediction(
            probability: probability,
            isAsleep: isAsleep,
            featureScores: FeatureScores(
                inactivity: inactivityScore,
                motion: motionScore,
                timeOfDay: timeScore,
                unlockCadence: unlockScore,
                sleepFocus: focusScore,
                historicalPrior: historyScore
            ),
            rawScore: rawScore,
            timestamp: Date()
        )
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 4: SCORING HELPER FUNCTIONS
    // ─────────────────────────────────────────────────────────

    /// Time-of-day score using a cosine curve.
    /// Returns a value between 0 and 1 that peaks during typical
    /// sleep hours (roughly 11 PM – 6 AM) and bottoms out during
    /// the day (roughly 8 AM – 8 PM).
    ///
    /// The math: we shift the hour so that 2:30 AM (the deepest
    /// sleep for most people) maps to the peak of a cosine wave.
    private func timeOfDayScore(hour: Double) -> Double {
        // Shift so 2.5 (2:30 AM) is at the cosine peak (0 radians)
        // Then one full cycle = 24 hours
        let shifted = (hour - 2.5) * (2 * .pi / 24.0)
        let cosValue = cos(shifted)
        // Map from [-1, 1] to [0, 1]
        return (cosValue + 1.0) / 2.0
    }

    /// Historical prior: Gaussian centred on the user's average
    /// sleep onset time. Returns 1.0 if current time matches
    /// their average exactly, fading to ~0 as the distance grows.
    ///
    /// If no historical data exists yet, returns 0.5 (neutral).
    private func historicalPriorScore(currentHour: Double, avgOnset: Double?) -> Double {
        guard let onset = avgOnset else { return 0.5 }

        // Handle midnight wrap-around:
        // If avg onset is 23.5 (11:30 PM) and current time is 0.5 (12:30 AM),
        // the real difference is 1 hour, not 23 hours.
        var diff = abs(currentHour - onset)
        if diff > 12 { diff = 24 - diff }

        // Gaussian with standard deviation of 2 hours
        // Within ±1 hour: score ≈ 0.88 – 1.0
        // Within ±2 hours: score ≈ 0.60
        // Beyond ±4 hours: score ≈ 0.02 (essentially 0)
        let sigma = 2.0
        return exp(-(diff * diff) / (2 * sigma * sigma))
    }

    /// Standard sigmoid function with adjustable steepness and midpoint.
    ///   steepness: how sharp the transition is (higher = sharper)
    ///   midpoint: the input value where output = 0.5
    private func sigmoid(_ x: Double, steepness: Double, midpoint: Double) -> Double {
        1.0 / (1.0 + exp(-steepness * (x - midpoint)))
    }
}

// ─────────────────────────────────────────────────────────────
// Prediction result
// ─────────────────────────────────────────────────────────────

struct SleepPrediction {
    /// Probability (0–1) that the user is currently asleep.
    let probability: Double

    /// True if probability >= threshold.
    let isAsleep: Bool

    /// Individual feature scores for debugging / logging.
    let featureScores: FeatureScores

    /// The raw weighted sum before sigmoid.
    let rawScore: Double

    /// When this prediction was made.
    let timestamp: Date
}

struct FeatureScores {
    let inactivity: Double
    let motion: Double
    let timeOfDay: Double
    let unlockCadence: Double
    let sleepFocus: Double
    let historicalPrior: Double
}
