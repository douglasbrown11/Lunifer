import SwiftUI

// ─────────────────────────────────────────────────────────────
// SleepInsights
// ─────────────────────────────────────────────────────────────
// Accessible by swiping right from the dashboard.
// Shows:
//   1. Recommended optimal sleep duration (top)
//   2. Sleep history range selector and tappable chart

struct SleepInsights: View {
    @Binding var answers: SurveyAnswers

    /// Injected entries for SwiftUI previews. Nil in production — falls back to the live store.
    var previewEntries: [SleepHistoryEntry]? = nil

    private var isRunningPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    @State private var showSettings = false
    @State private var selectedRange: SleepInsightsRange = .oneWeek
    @State private var selectedPointID: String?

    // Wearable state — read directly from AppStorage so changes sync immediately
    @AppStorage(AppPreferencesStore.Keys.hasWearable)               private var hasWearable: Bool      = false
    @AppStorage(AppPreferencesStore.Keys.whoopConnected)            private var whoopConnected: Bool   = false
    @AppStorage(AppPreferencesStore.Keys.whoopRecommendedSleepHours) private var whoopSleepHours: Double = 0
    @AppStorage(AppPreferencesStore.Keys.ouraConnected)             private var ouraConnected: Bool    = false
    @AppStorage(AppPreferencesStore.Keys.ouraRecommendedSleepHours)  private var ouraSleepHours: Double  = 0

    // Pull complete local sleep history from the manager (or injected preview data).
    private var allStoredHistory: [SleepHistoryEntry] {
        previewEntries ?? SleepHistoryManager.shared.allHistory()
    }

    private var visibleHistory: [SleepHistoryEntry] {
        let sortedHistory = allStoredHistory.sorted { $0.date > $1.date }

        guard let cutoff = selectedRange.cutoffDate(referenceDate: Date()) else {
            return sortedHistory
        }

        return sortedHistory.filter { $0.date >= cutoff }
    }

    private var chartPoints: [SleepHistoryChartPoint] {
        SleepHistoryChartPoint.points(
            from: visibleHistory,
            range: selectedRange,
            recommendedHours: recommendedHours
        )
    }

    private var selectedPoint: SleepHistoryChartPoint? {
        chartPoints.first { $0.id == selectedPointID } ?? chartPoints.last
    }

    private var wearableSources: [WearableRecommendationSource] {
        WearableRecommendationStore.sources(
            whoopConnected: whoopConnected,
            whoopRecommendedSleepHours: whoopSleepHours,
            ouraConnected: ouraConnected,
            ouraRecommendedSleepHours: ouraSleepHours
        )
    }

    private var userHasWearable: Bool {
        hasWearable || WearableRecommendationStore.hasWearable(from: wearableSources)
    }

    private var wearableRecommendation: WearableRecommendation? {
        guard userHasWearable else { return nil }
        return WearableRecommendationStore.activeRecommendation(from: wearableSources)
    }

    // Flow: wearable recommendation -> manual preference -> age baseline
    private var recommendedHours: Double {
        guard userHasWearable else {
            return WearableRecommendationStore.fallbackSleepHours(from: answers)
        }

        return WearableRecommendationStore.recommendedHours(from: wearableSources, fallback: answers)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {

                Spacer().frame(height: 28)

                // ── Optimal sleep duration card ──────────
                VStack(spacing: 10) {

                    // Subtle link to the sleep editor in Settings
                    HStack {
                        Spacer()
                        Button {
                            showSettings = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("Adjust in Settings")
                                    .font(.custom("DM Sans", size: 12))
                                    .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.7))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.5))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 14)
                        .padding(.leading, 3)
                    }

                    Text("SLEEP")
                        .font(.custom("DM Sans", size: 11))
                        .foregroundColor(Color.white.opacity(0.35))
                        .kerning(2.5)

                    Text(SleepDurationModel.formatted(recommendedHours))
                        .font(.libreFranklin(size: 44))
                        .foregroundColor(Color.white.opacity(0.95))

                    // "recommended to you via [logo]" — or plain text if no wearable
                    if let recommendation = wearableRecommendation {
                        HStack(spacing: 6) {
                            Text("recommended to you via")
                                .font(.custom("DM Sans", size: 13))
                                .foregroundColor(Color.white.opacity(0.4))
                            Image(recommendation.provider.wordmarkAssetName)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(height: 13)
                        }
                        .transition(.opacity)
                    } else {
                        Text("recommended for you")
                            .font(.custom("DM Sans", size: 13))
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 60)

                Spacer().frame(height: 16)

                SleepRangeSelector(selectedRange: $selectedRange)
                    .padding(.horizontal, 60)

                Spacer().frame(height: 16)

                // ── History chart ─────────────────────────
                HStack {
                    Text("SLEEP HISTORY")
                        .font(.custom("DM Sans", size: 11))
                        .foregroundColor(Color.white.opacity(0.35))
                        .kerning(2.5)
                    Spacer()
                    Text(selectedRange.subtitle)
                        .font(.custom("DM Sans", size: 11))
                        .foregroundColor(Color.white.opacity(0.28))
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 10)

                Group {
                    if chartPoints.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "moon.zzz")
                                .font(.system(size: 28, weight: .ultraLight))
                                .foregroundColor(Color.white.opacity(0.2))

                            Text("Sleep data will appear here\nafter your first night")
                                .font(.custom("DM Sans", size: 13))
                                .foregroundColor(Color.white.opacity(0.3))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    } else {
                        SleepHistoryChart(
                            points: chartPoints,
                            selectedPointID: $selectedPointID
                        )
                        .frame(height: 150)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 60)

                if let selectedPoint {
                    Spacer().frame(height: 14)

                    SleepInsightDetailCard(
                        point: selectedPoint,
                        recommendedHours: recommendedHours
                    )
                    .padding(.horizontal, 60)
                }

                Spacer().frame(height: 28)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            syncSelectedPoint()
            guard !isRunningPreview else { return }
            WhoopManager.shared.refreshIfNeeded()
            OuraManager.shared.refreshIfNeeded()
        }
        .onChange(of: selectedRange) { _, _ in
            syncSelectedPoint(preferLatest: true)
        }
        .onChange(of: chartPoints.map(\.id)) { _, _ in
            syncSelectedPoint()
        }
        // ── Jump to Sleep & Wearables settings ───────────
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SleepAndWearablesSettingsView(answers: $answers)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(red: 0.06, green: 0.03, blue: 0.14))
        }
    }

    private func syncSelectedPoint(preferLatest: Bool = false) {
        guard !chartPoints.isEmpty else {
            selectedPointID = nil
            return
        }

        if preferLatest || !chartPoints.contains(where: { $0.id == selectedPointID }) {
            selectedPointID = chartPoints.last?.id
        }
    }
}

private enum SleepInsightsRange: String, CaseIterable, Identifiable {
    case oneWeek = "1W"
    case oneMonth = "1M"
    case sixMonths = "6M"
    case yearToDate = "YTD"
    case maximum = "Max"

    var id: String { rawValue }

    func cutoffDate(referenceDate: Date) -> Date? {
        let calendar = Calendar.current

        switch self {
        case .oneWeek:
            return calendar.date(byAdding: .day, value: -7, to: referenceDate)
        case .oneMonth:
            return calendar.date(byAdding: .month, value: -1, to: referenceDate)
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: referenceDate)
        case .yearToDate:
            let year = calendar.component(.year, from: referenceDate)
            return calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        case .maximum:
            return nil
        }
    }

    var subtitle: String {
        switch self {
        case .oneWeek:
            return "daily"
        case .oneMonth:
            return "weekly"
        case .sixMonths:
            return "monthly"
        case .yearToDate:
            return "monthly"
        case .maximum:
            return "monthly"
        }
    }

    var aggregation: SleepHistoryAggregation {
        switch self {
        case .oneWeek:
            return .night
        case .oneMonth:
            return .week
        case .sixMonths, .yearToDate, .maximum:
            return .month
        }
    }
}

private enum SleepHistoryAggregation {
    case night
    case week
    case month
}

private struct SleepRangeSelector: View {
    @Binding var selectedRange: SleepInsightsRange

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SleepInsightsRange.allCases) { range in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedRange = range
                    }
                } label: {
                    Text(range.rawValue)
                        .font(.custom("DM Sans", size: 11).weight(.medium))
                        .foregroundColor(selectedRange == range ? .white : Color.white.opacity(0.42))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            Capsule()
                                .fill(
                                    selectedRange == range
                                    ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.28)
                                    : Color.clear
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.045))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct SleepHistoryChartPoint: Identifiable, Equatable {
    let id: String
    let startDate: Date
    let endDate: Date
    let durationHours: Double
    let entryCount: Int
    let label: String
    let title: String
    let sleepOnset: Date?
    let wakeTime: Date?
    let metTarget: Bool

    var isAggregate: Bool {
        entryCount > 1
    }

    static func points(
        from entries: [SleepHistoryEntry],
        range: SleepInsightsRange,
        recommendedHours: Double
    ) -> [SleepHistoryChartPoint] {
        let ascendingEntries = entries.sorted { $0.date < $1.date }

        switch range.aggregation {
        case .night:
            return ascendingEntries.map { entry in
                let isToday = Calendar.current.isDateInToday(entry.date)
                return SleepHistoryChartPoint(
                    id: "night-\(Int(entry.date.timeIntervalSince1970))",
                    startDate: entry.date,
                    endDate: entry.date,
                    durationHours: entry.durationHours,
                    entryCount: 1,
                    label: range == .oneWeek ? (isToday ? "Today" : entry.dayLabel) : dayOfMonthLabel(entry.date),
                    title: fullDateLabel(entry.date),
                    sleepOnset: entry.sleepOnset,
                    wakeTime: entry.wakeTime,
                    metTarget: entry.durationHours >= recommendedHours
                )
            }

        case .week:
            return groupedPoints(
                from: ascendingEntries,
                component: .weekOfYear,
                recommendedHours: recommendedHours,
                label: { weekLabel($0) },
                title: { start, end in rangeLabel(start: start, end: end) }
            )

        case .month:
            return groupedPoints(
                from: ascendingEntries,
                component: .month,
                recommendedHours: recommendedHours,
                label: { monthLabel($0, includeYear: range == .maximum) },
                title: { start, _ in monthTitle(start) }
            )
        }
    }

    private static func groupedPoints(
        from entries: [SleepHistoryEntry],
        component: Calendar.Component,
        recommendedHours: Double,
        label: (Date) -> String,
        title: (Date, Date) -> String
    ) -> [SleepHistoryChartPoint] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: entries) { entry in
            calendar.dateInterval(of: component, for: entry.date)?.start
                ?? calendar.startOfDay(for: entry.date)
        }

        return groups.map { groupStart, groupedEntries in
            let sortedGroup = groupedEntries.sorted { $0.date < $1.date }
            let average = sortedGroup.reduce(0) { $0 + $1.durationHours } / Double(sortedGroup.count)
            let end = calendar.dateInterval(of: component, for: groupStart)?.end.addingTimeInterval(-1)
                ?? sortedGroup.last?.date
                ?? groupStart

            return SleepHistoryChartPoint(
                id: "\(component)-\(Int(groupStart.timeIntervalSince1970))",
                startDate: groupStart,
                endDate: end,
                durationHours: average,
                entryCount: sortedGroup.count,
                label: label(groupStart),
                title: title(groupStart, end),
                sleepOnset: nil,
                wakeTime: nil,
                metTarget: average >= recommendedHours
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }

    private static func dayOfMonthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private static func weekLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private static func monthLabel(_ date: Date, includeYear: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = includeYear ? "MMM yy" : "MMM"
        return formatter.string(from: date)
    }

    private static func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private static func fullDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    private static func rangeLabel(start: Date, end: Date) -> String {
        "\(shortDateLabel(start)) - \(shortDateLabel(end))"
    }

    private static func shortDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

private struct SleepInsightDetailCard: View {
    let point: SleepHistoryChartPoint
    let recommendedHours: Double

    private var deltaHours: Double {
        point.durationHours - recommendedHours
    }

    private var statusText: String {
        if abs(deltaHours) < 0.1 {
            return "On target"
        }

        return deltaHours > 0 ? "Surplus" : "Debt"
    }

    private var statusColor: Color {
        if deltaHours >= -0.1 {
            return Color(red: 0.627, green: 0.471, blue: 1.0)
        }

        return Color(red: 1.0, green: 0.56, blue: 0.56)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(point.isAggregate ? "Average Sleep" : "Night Sleep")
                        .font(.custom("DM Sans", size: 11))
                        .kerning(2.0)
                        .foregroundColor(Color.white.opacity(0.35))

                    Text(point.title)
                        .font(.custom("DM Sans", size: 15).weight(.medium))
                        .foregroundColor(Color.white.opacity(0.82))
                }

                Spacer()

                Text(statusText)
                    .font(.custom("DM Sans", size: 11).weight(.medium))
                    .foregroundColor(statusColor.opacity(0.95))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(statusColor.opacity(0.12))
                    )
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(SleepDurationModel.formatted(point.durationHours))
                    .font(.libreFranklin(size: 32))
                    .foregroundColor(.white.opacity(0.96))

                Text(point.isAggregate ? "average" : "recorded")
                    .font(.custom("DM Sans", size: 12))
                    .foregroundColor(Color.white.opacity(0.35))
            }

            VStack(spacing: 9) {
                detailRow("Target", SleepDurationModel.formatted(recommendedHours))
                detailRow(deltaHours >= 0 ? "Above target" : "Below target", SleepDurationModel.formatted(abs(deltaHours)))

                if point.isAggregate {
                    detailRow("Nights", "\(point.entryCount)")
                    detailRow("Range", "\(shortDate(point.startDate)) - \(shortDate(point.endDate))")
                } else {
                    detailRow("Bedtime", timeLabel(point.sleepOnset))
                    detailRow("Wake", timeLabel(point.wakeTime))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.custom("DM Sans", size: 12))
                .foregroundColor(Color.white.opacity(0.34))

            Spacer()

            Text(value)
                .font(.custom("DM Sans", size: 12).weight(.medium))
                .foregroundColor(Color.white.opacity(0.74))
        }
    }

    private func timeLabel(_ date: Date?) -> String {
        guard let date else { return "Not recorded" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// ─────────────────────────────────────────────────────────────
// SleepEditSheet after clicking "change"
// ─────────────────────────────────────────────────────────────

struct SleepEditSheet: View {
    @Binding var sleep: TimeValue
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Handle area
            Spacer().frame(height: 8)

            Text("Optimal Sleep Time")
                .font(.custom("Cormorant Garamond", size: 22).weight(.light))
                .foregroundColor(Color.white.opacity(0.9))
                .padding(.top, 20)
                .padding(.bottom, 24)

            TimeScalePicker(value: $sleep,
                            autoLabel: "I'm not sure — let Lunifer learn this",
                            hourRange: 0...12)
                .padding(.horizontal, 32)

            Spacer().frame(height: 28)

            Button(action: onSave) {
                Text("Save")
                    .font(.custom("DM Sans", size: 15).weight(.medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(LinearGradient(
                                colors: [
                                    Color(red: 0.471, green: 0.314, blue: 0.863).opacity(0.9),
                                    Color(red: 0.314, green: 0.196, blue: 0.706).opacity(0.9),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }
}

// ─────────────────────────────────────────────────────────────
// SleepHistoryChart
// ─────────────────────────────────────────────────────────────
// A tappable bar chart showing daily, weekly, or monthly sleep duration.

private struct SleepHistoryChart: View {
    let points: [SleepHistoryChartPoint]
    @Binding var selectedPointID: String?

    private var maxHours: Double {
        let tallest = points.map(\.durationHours).max() ?? 8
        return max(tallest + 1, 10)
    }

    var body: some View {
        GeometryReader { geo in
            let count = max(points.count, 1)
            let spacing = CGFloat(8)
            let desiredBarWidth = CGFloat(count > 40 ? 18 : (count > 16 ? 24 : 34))
            let contentWidth = max(
                geo.size.width,
                CGFloat(count) * desiredBarWidth + spacing * CGFloat(max(count - 1, 0))
            )
            let barWidth = min(
                max((contentWidth - spacing * CGFloat(count - 1)) / CGFloat(count), 8),
                42
            )

            // Vertical layout constants
            let showsDurationLabels = count <= 32
            let durLabelH = CGFloat(showsDurationLabels ? 16 : 0)
            let axisH = CGFloat(1)
            let xLabelH = CGFloat(22)
            let barAreaH = geo.size.height - axisH - xLabelH
            let barSlotH = barAreaH - durLabelH

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {

                    // ── Bar + duration-label area ────────────────
                    ZStack(alignment: .bottom) {
                        HStack(alignment: .bottom, spacing: spacing) {
                            ForEach(points) { point in
                                let isSelected = selectedPointID == point.id
                                let barH = max(barSlotH * (point.durationHours / maxHours), 4)

                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        selectedPointID = point.id
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        if showsDurationLabels {
                                            Text(SleepDurationModel.shortFormatted(point.durationHours))
                                                .font(.custom("DM Sans", size: 10))
                                                .foregroundColor(Color.white.opacity(isSelected ? 0.78 : 0.45))
                                                .frame(height: durLabelH)
                                        }

                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(barFill(for: point, isSelected: isSelected))
                                            .frame(width: barWidth, height: barH)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(
                                                        Color.white.opacity(isSelected ? 0.38 : 0),
                                                        lineWidth: 1
                                                    )
                                            )
                                    }
                                    .frame(width: barWidth)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(width: contentWidth)
                    }
                    .frame(width: contentWidth, height: barAreaH)

                    // ── X-axis divider ───────────────────────────
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: contentWidth, height: axisH)

                    // ── X-axis labels ────────────────────────────
                    HStack(spacing: spacing) {
                        ForEach(points) { point in
                            let isSelected = selectedPointID == point.id
                            Text(point.label)
                                .font(.custom("DM Sans", size: 11))
                                .foregroundColor(
                                    isSelected
                                    ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.9)
                                    : Color.white.opacity(0.4)
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: barWidth)
                        }
                    }
                    .frame(width: contentWidth)
                    .padding(.top, 5)
                    .frame(height: xLabelH)
                }
            }
        }
    }

    private func barFill(for point: SleepHistoryChartPoint, isSelected: Bool) -> Color {
        let base = Color(red: 0.627, green: 0.471, blue: 1.0)

        if isSelected {
            return base.opacity(0.9)
        }

        return point.metTarget ? base.opacity(0.58) : base.opacity(0.25)
    }
}

#Preview("Sleep Insights — no wearable") {
    @Previewable @State var answers: SurveyAnswers = {
        var a = SurveyAnswers()
        a.age = "22"
        return a
    }()
    ZStack {
        Color(red: 0.07, green: 0.04, blue: 0.15).ignoresSafeArea()
        SleepInsights(answers: $answers, previewEntries: SleepHistoryMock.entries)
    }
    .onAppear {
        UserDefaults.standard.set(false, forKey: "whoopConnected")
        UserDefaults.standard.set(false, forKey: "ouraConnected")
    }
}

#Preview("Sleep Insights — WHOOP") {
    @Previewable @State var answers: SurveyAnswers = {
        var a = SurveyAnswers()
        a.age = "22"
        return a
    }()
    ZStack {
        Color(red: 0.07, green: 0.04, blue: 0.15).ignoresSafeArea()
        SleepInsights(answers: $answers, previewEntries: SleepHistoryMock.entries)
    }
    .onAppear {
        UserDefaults.standard.set(true,  forKey: "whoopConnected")
        UserDefaults.standard.set(7.5,   forKey: "whoopRecommendedSleepHours")
        UserDefaults.standard.set(false, forKey: "ouraConnected")
    }
}

#Preview("Sleep Insights — Oura Ring") {
    @Previewable @State var answers: SurveyAnswers = {
        var a = SurveyAnswers()
        a.age = "22"
        return a
    }()
    ZStack {
        Color(red: 0.07, green: 0.04, blue: 0.15).ignoresSafeArea()
        SleepInsights(answers: $answers, previewEntries: SleepHistoryMock.entries)
    }
    .onAppear {
        UserDefaults.standard.set(false, forKey: "whoopConnected")
        UserDefaults.standard.set(true,  forKey: "ouraConnected")
        UserDefaults.standard.set(8.25,  forKey: "ouraRecommendedSleepHours")
    }
}

#Preview("Sleep History Chart — mock data") {
    @Previewable @State var selectedPointID: String? = nil
    let points = SleepHistoryChartPoint.points(
        from: SleepHistoryMock.entries,
        range: .oneWeek,
        recommendedHours: 8.0
    )

    ZStack {
        Color(red: 0.07, green: 0.04, blue: 0.15).ignoresSafeArea()
        SleepHistoryChart(
            points: points,
            selectedPointID: $selectedPointID
        )
        .frame(height: 200)
        .padding(.horizontal, 24)
    }
    .onAppear {
        selectedPointID = points.last?.id
    }
}
