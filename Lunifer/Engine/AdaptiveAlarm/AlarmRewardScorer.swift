import Foundation

enum AlarmRewardScorer {
    static func reward(
        outcome: String,
        observedAt: Date,
        scheduledWakeTime: Date?,
        alarmFiredAt: Date?,
        decision: AdaptiveAlarmDecision
    ) -> (reward: Double, actualSleepHours: Double?) {
        let actualSleepHours = matchingSleepDuration(near: observedAt)
        let sleepScore = sleepFitScore(
            actualSleepHours: actualSleepHours,
            recommendedSleepHours: decision.context.recommendedSleepHours
        )
        let wakeScore = wakeTimingScore(
            outcome: outcome,
            observedAt: observedAt,
            scheduledWakeTime: scheduledWakeTime ?? decision.finalAlarm,
            alarmFiredAt: alarmFiredAt
        )
        let safetyScore = decision.wasClamped ? 0.82 : 1.0

        let reward = 0.50 * sleepScore
            + 0.40 * wakeScore
            + 0.10 * safetyScore

        return (min(max(reward, 0.0), 1.0), actualSleepHours)
    }

    private static func sleepFitScore(
        actualSleepHours: Double?,
        recommendedSleepHours: Double
    ) -> Double {
        guard let actualSleepHours else {
            // Neutral: no reliable sleep-duration observation yet.
            return 0.55
        }

        let errorHours = abs(actualSleepHours - recommendedSleepHours)
        return min(max(1.0 - errorHours / 2.0, 0.0), 1.0)
    }

    private static func wakeTimingScore(
        outcome: String,
        observedAt: Date,
        scheduledWakeTime: Date,
        alarmFiredAt: Date?
    ) -> Double {
        switch outcome {
        case "woke_before_alarm":
            let leadMinutes = max(0.0, scheduledWakeTime.timeIntervalSince(observedAt) / 60.0)
            return min(max(0.55 - leadMinutes / 120.0, 0.05), 0.55)

        case "dismissed":
            let anchor = alarmFiredAt ?? scheduledWakeTime
            let lagMinutes = abs(observedAt.timeIntervalSince(anchor)) / 60.0
            return min(max(1.0 - lagMinutes / 45.0, 0.35), 1.0)

        default:
            return 0.5
        }
    }

    private static func matchingSleepDuration(near observedAt: Date) -> Double? {
        let calendar = Calendar.current
        let candidates = SleepHistoryStore.shared.recentHistory(days: 3)

        if let sameDay = candidates.first(where: { entry in
            if let wake = entry.wakeTime {
                return calendar.isDate(wake, inSameDayAs: observedAt)
            }
            return calendar.isDate(entry.date, inSameDayAs: observedAt)
        }) {
            return sameDay.durationHours
        }

        return candidates.first?.durationHours
    }
}
