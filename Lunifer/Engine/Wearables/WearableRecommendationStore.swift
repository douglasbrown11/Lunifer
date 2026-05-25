import Foundation

enum WearableProvider {
    case whoop
    case oura

    var displayName: String {
        switch self {
        case .whoop: return "WHOOP"
        case .oura:  return "Oura Ring"
        }
    }

    var wordmarkAssetName: String {
        switch self {
        case .whoop: return "WhoopWordmark"
        case .oura:  return "OuraWordmark"
        }
    }
}

struct WearableRecommendation {
    let provider: WearableProvider
    let hours: Double
}

struct WearableRecommendationSource {
    let provider: WearableProvider
    let isConnected: Bool
    let recommendedHours: Double
}

enum WearableRecommendationStore {
    static func currentSources() -> [WearableRecommendationSource] {
        let prefs = AppPreferencesStore.shared
        return sources(
            whoopConnected: prefs.whoopConnected,
            whoopRecommendedSleepHours: prefs.whoopRecommendedSleepHours,
            ouraConnected: prefs.ouraConnected,
            ouraRecommendedSleepHours: prefs.ouraRecommendedSleepHours
        )
    }

    static func sources(
        whoopConnected: Bool,
        whoopRecommendedSleepHours: Double,
        ouraConnected: Bool,
        ouraRecommendedSleepHours: Double
    ) -> [WearableRecommendationSource] {
        return [
            WearableRecommendationSource(
                provider: .whoop,
                isConnected: whoopConnected,
                recommendedHours: whoopRecommendedSleepHours
            ),
            WearableRecommendationSource(
                provider: .oura,
                isConnected: ouraConnected,
                recommendedHours: ouraRecommendedSleepHours
            )
        ]
    }

    static func activeRecommendation(from sources: [WearableRecommendationSource]) -> WearableRecommendation? {
        sources
            .first { $0.isConnected && $0.recommendedHours > 0 }
            .map { WearableRecommendation(provider: $0.provider, hours: $0.recommendedHours) }
    }

    static func hasWearable(from sources: [WearableRecommendationSource]) -> Bool {
        activeRecommendation(from: sources) != nil
    }

    static func recommendedHours(from sources: [WearableRecommendationSource], fallback answers: SurveyAnswers) -> Double {
        if let recommendation = activeRecommendation(from: sources) {
            return recommendation.hours
        }

        return fallbackSleepHours(from: answers)
    }

    static func fallbackSleepHours(from answers: SurveyAnswers) -> Double {
        if answers.sleep.auto {
            return SleepDurationModel.baselineForAge(answers.age)
        }

        return Double(answers.sleep.hours) + Double(answers.sleep.minutes) / 60.0
    }
}
