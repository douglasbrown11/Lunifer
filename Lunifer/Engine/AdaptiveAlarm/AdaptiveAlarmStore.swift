import Foundation

final class AdaptiveAlarmStore {
    static let shared = AdaptiveAlarmStore()

    private let defaults = UserDefaults.standard
    private let pendingDecisionKey = "adaptiveAlarmPendingDecision"
    private let outcomesKey = "adaptiveAlarmOutcomes"
    private let maxOutcomes = 120

    private init() {}

    func savePendingDecision(_ decision: AdaptiveAlarmDecision) {
        guard let data = try? JSONEncoder().encode(decision) else { return }
        defaults.set(data, forKey: pendingDecisionKey)
    }

    func pendingDecision() -> AdaptiveAlarmDecision? {
        guard let data = defaults.data(forKey: pendingDecisionKey) else { return nil }
        return try? JSONDecoder().decode(AdaptiveAlarmDecision.self, from: data)
    }

    func clearPendingDecision() {
        defaults.removeObject(forKey: pendingDecisionKey)
    }

    func recentOutcomes(limit: Int = 120) -> [AdaptiveAlarmOutcome] {
        let outcomes = loadOutcomes()
        return Array(outcomes.suffix(limit))
    }

    func markPendingDecisionIneligible() {
        guard var decision = pendingDecision() else { return }
        decision.trainingEligible = false
        savePendingDecision(decision)
    }

    func updatePendingFinalAlarm(to finalAlarm: Date) {
        guard var decision = pendingDecision() else { return }
        let actualOffset = Int(round(finalAlarm.timeIntervalSince(decision.baselineAlarm) / 60.0))

        decision.finalAlarm = finalAlarm
        decision.wasClamped = decision.wasClamped || !decision.safetyWindow.allows(finalAlarm)

        if (-60...60).contains(actualOffset) {
            decision.selectedOffsetMinutes = actualOffset
        } else {
            decision.trainingEligible = false
        }

        savePendingDecision(decision)
    }

    func recordOutcome(
        outcome: String,
        observedAt: Date,
        scheduledWakeTime: Date?,
        alarmFiredAt: Date?
    ) -> AdaptiveAlarmOutcome? {
        guard let decision = pendingDecision() else { return nil }
        defer { clearPendingDecision() }

        guard decision.trainingEligible else { return nil }

        let score = AlarmRewardScorer.reward(
            outcome: outcome,
            observedAt: observedAt,
            scheduledWakeTime: scheduledWakeTime,
            alarmFiredAt: alarmFiredAt,
            decision: decision
        )

        let adaptiveOutcome = AdaptiveAlarmOutcome(
            id: UUID(),
            decisionID: decision.id,
            observedAt: observedAt,
            outcome: outcome,
            reward: score.reward,
            actualSleepHours: score.actualSleepHours,
            recommendedSleepHours: decision.context.recommendedSleepHours,
            selectedOffsetMinutes: decision.selectedOffsetMinutes,
            context: decision.context
        )

        var outcomes = loadOutcomes()
        outcomes.append(adaptiveOutcome)
        if outcomes.count > maxOutcomes {
            outcomes = Array(outcomes.suffix(maxOutcomes))
        }
        saveOutcomes(outcomes)

        return adaptiveOutcome
    }

    func clearLocalData() {
        defaults.removeObject(forKey: pendingDecisionKey)
        defaults.removeObject(forKey: outcomesKey)
    }

    private func loadOutcomes() -> [AdaptiveAlarmOutcome] {
        guard let data = defaults.data(forKey: outcomesKey),
              let outcomes = try? JSONDecoder().decode([AdaptiveAlarmOutcome].self, from: data) else {
            return []
        }
        return outcomes
    }

    private func saveOutcomes(_ outcomes: [AdaptiveAlarmOutcome]) {
        guard let data = try? JSONEncoder().encode(outcomes) else { return }
        defaults.set(data, forKey: outcomesKey)
    }
}
