import Foundation
import FirebaseAuth
import FirebaseFirestore

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

    // ── Firestore sync ────────────────────────────────────────

    /// Pulls adaptive outcomes from Firestore and merges them with whatever
    /// is stored locally. Call this after sign-in so outcomes survive
    /// reinstalls, factory resets, and device upgrades.
    func loadFromFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let doc = try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("adaptiveData").document("outcomes")
                .getDocument()

            guard let jsonString = doc.data()?["outcomes"] as? String,
                  let data = jsonString.data(using: .utf8),
                  let remoteOutcomes = try? JSONDecoder().decode([AdaptiveAlarmOutcome].self, from: data)
            else { return }

            // Merge remote + local, deduplicate by ID, keep newest maxOutcomes.
            let localOutcomes = loadOutcomes()
            let localIDs = Set(localOutcomes.map(\.id))
            let newFromRemote = remoteOutcomes.filter { !localIDs.contains($0.id) }
            var merged = (localOutcomes + newFromRemote).sorted { $0.observedAt < $1.observedAt }
            if merged.count > maxOutcomes { merged = Array(merged.suffix(maxOutcomes)) }

            // Save merged set locally (no Firestore write — remote already has it).
            guard let encoded = try? JSONEncoder().encode(merged) else { return }
            defaults.set(encoded, forKey: outcomesKey)

            print("✅ Adaptive outcomes loaded from Firestore (\(remoteOutcomes.count) remote, \(merged.count) after merge)")
        } catch {
            print("❌ Failed to load adaptive outcomes from Firestore: \(error.localizedDescription)")
        }
    }

    // ── Private helpers ───────────────────────────────────────

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
        syncToFirestore(outcomes)
    }

    /// Writes the full outcomes array to Firestore as a JSON string.
    /// Fires-and-forgets — a write failure doesn't affect the local state.
    private func syncToFirestore(_ outcomes: [AdaptiveAlarmOutcome]) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let data = try? JSONEncoder().encode(outcomes),
              let jsonString = String(data: data, encoding: .utf8) else { return }

        Firestore.firestore()
            .collection("users").document(uid)
            .collection("adaptiveData").document("outcomes")
            .setData(["outcomes": jsonString, "updatedAt": Date()]) { error in
                if let error {
                    print("❌ Failed to sync adaptive outcomes to Firestore: \(error.localizedDescription)")
                } else {
                    print("✅ Adaptive outcomes synced to Firestore (\(outcomes.count) entries)")
                }
            }
    }
}
