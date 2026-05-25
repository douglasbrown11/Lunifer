import Foundation

struct AdaptiveAlarmContext: Codable {
    let targetWeekday: Int
    let baselineMinuteOfDay: Int
    let expectedBedtimeMinuteOfDay: Int
    let recommendedSleepHours: Double
    let priorNightSleepHours: Double?
    let recentAverageSleepHours: Double?
    let sleepDebtHours: Double
    let routineMinutes: Int
    let commuteMinutes: Int
    let calendarPressureMinutes: Int?
    let hasWearable: Bool
}

struct AdaptiveAlarmSafetyWindow: Codable {
    let earliestAllowedAlarm: Date
    let latestAllowedAlarm: Date

    func allows(_ alarm: Date) -> Bool {
        alarm >= earliestAllowedAlarm && alarm <= latestAllowedAlarm
    }

    func clamped(_ alarm: Date) -> Date {
        min(max(alarm, earliestAllowedAlarm), latestAllowedAlarm)
    }
}

struct AdaptiveAlarmDecision: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let baselineAlarm: Date
    var finalAlarm: Date
    var selectedOffsetMinutes: Int
    let context: AdaptiveAlarmContext
    let safetyWindow: AdaptiveAlarmSafetyWindow
    let expectedReward: Double
    let uncertainty: Double
    var wasClamped: Bool
    var trainingEligible: Bool
}

struct AdaptiveAlarmOutcome: Codable {
    let id: UUID
    let decisionID: UUID
    let observedAt: Date
    let outcome: String
    let reward: Double
    let actualSleepHours: Double?
    let recommendedSleepHours: Double
    let selectedOffsetMinutes: Int
    let context: AdaptiveAlarmContext
}
