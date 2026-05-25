import Foundation

enum AlarmContextBuilder {
    @MainActor
    static func build(
        answers: SurveyAnswers,
        baselineAlarm: Date,
        routineMinutes: Int,
        commuteMinutes: Int,
        firstEvent: CalendarEvent?
    ) -> AdaptiveAlarmContext {
        let sources = WearableRecommendationStore.currentSources()
        let hasWearable = AppPreferencesStore.shared.hasWearable
            || WearableRecommendationStore.hasWearable(from: sources)
        let recommendedSleepHours = WearableRecommendationStore.recommendedHours(
            from: sources,
            fallback: answers
        )

        let recentHistory = SleepHistoryStore.shared.recentHistory(days: 7)
        let priorNightSleepHours = recentHistory.first?.durationHours
        let recentAverageSleepHours = SleepHistoryStore.shared.averageDuration(days: 7)
        let sleepReference = priorNightSleepHours ?? recentAverageSleepHours ?? recommendedSleepHours
        let sleepDebtHours = recommendedSleepHours - sleepReference

        let calendarPressureMinutes = firstEvent.map {
            Int(round($0.startDate.timeIntervalSince(baselineAlarm) / 60.0))
        }

        let expectedBedtime = baselineAlarm.addingTimeInterval(-recommendedSleepHours * 3600)
        let calendar = Calendar.current

        return AdaptiveAlarmContext(
            targetWeekday: calendar.component(.weekday, from: baselineAlarm),
            baselineMinuteOfDay: minuteOfDay(for: baselineAlarm, calendar: calendar),
            expectedBedtimeMinuteOfDay: minuteOfDay(for: expectedBedtime, calendar: calendar),
            recommendedSleepHours: recommendedSleepHours,
            priorNightSleepHours: priorNightSleepHours,
            recentAverageSleepHours: recentAverageSleepHours,
            sleepDebtHours: sleepDebtHours,
            routineMinutes: routineMinutes,
            commuteMinutes: commuteMinutes,
            calendarPressureMinutes: calendarPressureMinutes,
            hasWearable: hasWearable
        )
    }

    private static func minuteOfDay(for date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}
