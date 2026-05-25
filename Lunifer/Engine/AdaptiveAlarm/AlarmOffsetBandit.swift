import Foundation

enum AlarmOffsetBandit {
    private static let offsetRange = -60...60
    private static let offsetSigmaMinutes = 12.0
    private static let contextSigma = 1.0
    private static let explorationWeight = 0.08
    private static let stabilityWeight = 0.04

    static func chooseDecision(
        baselineAlarm: Date,
        context: AdaptiveAlarmContext,
        safetyWindow: AdaptiveAlarmSafetyWindow,
        outcomes: [AdaptiveAlarmOutcome]
    ) -> AdaptiveAlarmDecision {
        let validOffsets = offsetRange.filter { offset in
            let candidate = baselineAlarm.addingTimeInterval(Double(offset) * 60)
            return safetyWindow.allows(candidate)
        }

        let offsetsToScore = validOffsets.isEmpty ? [0] : validOffsets

        var bestOffset = 0
        var bestExpectedReward = 0.0
        var bestUncertainty = 0.0
        var bestScore = -Double.greatestFiniteMagnitude

        for offset in offsetsToScore {
            let estimate = estimateReward(
                context: context,
                offset: offset,
                outcomes: outcomes
            )
            let stabilityPenalty = stabilityWeight * (Double(abs(offset)) / 60.0)
            let score = estimate.expectedReward
                + explorationWeight * estimate.uncertainty
                - stabilityPenalty

            if score > bestScore || (score == bestScore && abs(offset) < abs(bestOffset)) {
                bestScore = score
                bestOffset = offset
                bestExpectedReward = estimate.expectedReward
                bestUncertainty = estimate.uncertainty
            }
        }

        let candidateAlarm = baselineAlarm.addingTimeInterval(Double(bestOffset) * 60)
        let finalAlarm = safetyWindow.clamped(candidateAlarm)
        let actualOffset = Int(round(finalAlarm.timeIntervalSince(baselineAlarm) / 60.0))

        return AdaptiveAlarmDecision(
            id: UUID(),
            createdAt: Date(),
            baselineAlarm: baselineAlarm,
            finalAlarm: finalAlarm,
            selectedOffsetMinutes: actualOffset,
            context: context,
            safetyWindow: safetyWindow,
            expectedReward: bestExpectedReward,
            uncertainty: bestUncertainty,
            wasClamped: abs(finalAlarm.timeIntervalSince(candidateAlarm)) > 1,
            trainingEligible: offsetRange.contains(actualOffset)
        )
    }

    private static func estimateReward(
        context: AdaptiveAlarmContext,
        offset: Int,
        outcomes: [AdaptiveAlarmOutcome]
    ) -> (expectedReward: Double, uncertainty: Double) {
        var weightedReward = 0.0
        var totalWeight = 0.0

        for outcome in outcomes {
            let contextWeight = kernelWeight(
                distanceSquared: contextDistanceSquared(context, outcome.context),
                sigma: contextSigma
            )
            let offsetDelta = Double(offset - outcome.selectedOffsetMinutes)
            let offsetWeight = exp(-(offsetDelta * offsetDelta) / (2 * offsetSigmaMinutes * offsetSigmaMinutes))
            let weight = contextWeight * offsetWeight

            guard weight > 0.0001 else { continue }
            weightedReward += weight * adjustedReward(
                for: outcome,
                candidateOffset: offset
            )
            totalWeight += weight
        }

        let priorReward = 0.58 - 0.05 * (Double(abs(offset)) / 60.0)
        let priorWeight = 0.45
        let expectedReward: Double
        if totalWeight > 0 {
            expectedReward = (weightedReward + priorReward * priorWeight) / (totalWeight + priorWeight)
        } else {
            expectedReward = priorReward
        }

        let uncertainty = 1.0 / sqrt(totalWeight + 1.0)
        return (expectedReward, uncertainty)
    }

    private static func adjustedReward(
        for outcome: AdaptiveAlarmOutcome,
        candidateOffset: Int
    ) -> Double {
        var reward = outcome.reward

        if outcome.outcome == "woke_before_alarm" {
            let earlierMinutes = Double(outcome.selectedOffsetMinutes - candidateOffset)
            let direction = min(max(earlierMinutes / 30.0, -1.0), 1.0)
            reward += 0.18 * direction
        } else if outcome.outcome == "dismissed",
                  let actualSleepHours = outcome.actualSleepHours {
            let sleepShortfall = outcome.recommendedSleepHours - actualSleepHours
            let laterMinutes = Double(candidateOffset - outcome.selectedOffsetMinutes)
            let sleepNeedSignal = min(max(sleepShortfall / 1.5, -1.0), 1.0)
            let direction = min(max(laterMinutes / 30.0, -1.0), 1.0)
            reward += 0.10 * sleepNeedSignal * direction
        }

        return min(max(reward, 0.0), 1.0)
    }

    private static func kernelWeight(distanceSquared: Double, sigma: Double) -> Double {
        exp(-distanceSquared / (2 * sigma * sigma))
    }

    private static func contextDistanceSquared(
        _ lhs: AdaptiveAlarmContext,
        _ rhs: AdaptiveAlarmContext
    ) -> Double {
        var distance = 0.0

        accumulate(&distance, circularWeekdayDistance(lhs.targetWeekday, rhs.targetWeekday) / 3.5)
        accumulate(&distance, circularMinuteDistance(lhs.baselineMinuteOfDay, rhs.baselineMinuteOfDay) / 360.0)
        accumulate(&distance, circularMinuteDistance(lhs.expectedBedtimeMinuteOfDay, rhs.expectedBedtimeMinuteOfDay) / 360.0)
        accumulate(&distance, (lhs.recommendedSleepHours - rhs.recommendedSleepHours) / 2.0)
        accumulate(&distance, (lhs.sleepDebtHours - rhs.sleepDebtHours) / 2.0)
        accumulate(&distance, Double(lhs.routineMinutes - rhs.routineMinutes) / 90.0)
        accumulate(&distance, Double(lhs.commuteMinutes - rhs.commuteMinutes) / 90.0)

        if let lhsPressure = lhs.calendarPressureMinutes,
           let rhsPressure = rhs.calendarPressureMinutes {
            accumulate(&distance, Double(lhsPressure - rhsPressure) / 180.0)
        } else if lhs.calendarPressureMinutes != nil || rhs.calendarPressureMinutes != nil {
            accumulate(&distance, 0.5)
        }

        if let lhsPrior = lhs.priorNightSleepHours,
           let rhsPrior = rhs.priorNightSleepHours {
            accumulate(&distance, (lhsPrior - rhsPrior) / 2.0)
        }

        if let lhsAverage = lhs.recentAverageSleepHours,
           let rhsAverage = rhs.recentAverageSleepHours {
            accumulate(&distance, (lhsAverage - rhsAverage) / 2.0)
        }

        if lhs.hasWearable != rhs.hasWearable {
            accumulate(&distance, 0.35)
        }

        return distance
    }

    private static func accumulate(_ total: inout Double, _ normalizedDifference: Double) {
        total += normalizedDifference * normalizedDifference
    }

    private static func circularWeekdayDistance(_ lhs: Int, _ rhs: Int) -> Double {
        let raw = abs(lhs - rhs)
        return Double(min(raw, 7 - raw))
    }

    private static func circularMinuteDistance(_ lhs: Int, _ rhs: Int) -> Double {
        let raw = abs(lhs - rhs)
        return Double(min(raw, 1440 - raw))
    }
}
