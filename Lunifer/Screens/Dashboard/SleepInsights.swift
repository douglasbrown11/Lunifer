import SwiftUI

// Builds an AttributedString where the numeric parts use `size` and the
// "hrs" / "m" suffixes are 5 points smaller, used by sleep duration displays.
fileprivate func formattedDurationAttributed(_ hours: Double, size: CGFloat) -> AttributedString {
    let h      = Int(hours)
    let m      = Int((hours - Double(h)) * 60)
    let numFont = Font.custom("Poppins", size: size)
    let sufFont = Font.custom("Poppins", size: size - 10)

    var result  = AttributedString()

    var numPart = AttributedString("\(h)")
    numPart.font = numFont
    result += numPart

    if m == 0 {
        var hrsPart = AttributedString(" hours")
        hrsPart.font = sufFont
        result += hrsPart
    } else {
        var hrsPart = AttributedString("hrs")
        hrsPart.font = sufFont
        result += hrsPart

        var mNum  = AttributedString(" \(m)")
        mNum.font = numFont
        result   += mNum

        var mSuf  = AttributedString("m")
        mSuf.font = sufFont
        result   += mSuf
    }

    return result
}

// ─────────────────────────────────────────────────────────────
// SleepInsights
// ─────────────────────────────────────────────────────────────
// Accessible by swiping right from the dashboard.
// Shows recommended optimal sleep duration and recent wake-time history.

struct SleepInsights: View {
    @Binding var answers: SurveyAnswers

    /// Injected entries for SwiftUI previews. Nil in production — falls back to the live store.
    var previewEntries: [SleepHistoryEntry]? = nil

    private var isRunningPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    @State private var showSettings = false

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

    private var wakeHistoryPoints: [WakeHistoryPoint] {
        WakeHistoryPoint.points(from: allStoredHistory, referenceDate: Date())
    }

    private var averageWakeTime: Date? {
        WakeHistoryPoint.averageWakeTime(from: wakeHistoryPoints)
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

    // Flow: wearable recommendation -> manual preference -> default baseline
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

                    Text("RECOMMENDED SLEEP")
                        .font(.custom("DM Sans", size: 11))
                        .foregroundColor(Color.white.opacity(0.35))
                        .kerning(2.5)

                    Text(formattedDurationAttributed(recommendedHours, size: 44))
                        .foregroundColor(Color.white.opacity(0.95))

                    // "recommended to you via [logo]" — only shown when a wearable
                    // is the source. No plain-text caption when there's no wearable.
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
                .walkthroughTarget(.sleepInsights)

                Spacer().frame(height: 16)

                WakeTimesCard(points: wakeHistoryPoints, averageWakeTime: averageWakeTime)
                    .padding(.horizontal, 60)

                Spacer().frame(height: 28)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !isRunningPreview else { return }
            WhoopManager.shared.refreshIfNeeded()
            OuraManager.shared.refreshIfNeeded()
            HealthKitManager.shared.refreshIfNeeded()
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
}

struct WakeHistoryPoint: Identifiable, Equatable {
    let id: String
    let date: Date
    let wakeTime: Date
    let label: String
    let minuteOfDay: Int

    static func points(from entries: [SleepHistoryEntry], referenceDate: Date) -> [WakeHistoryPoint] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -7, to: referenceDate) ?? referenceDate

        let entryPoints = entries
            .compactMap { entry -> SleepHistoryEntry? in
                guard let wakeTime = entry.wakeTime,
                      wakeTime >= cutoff,
                      wakeTime <= referenceDate else { return nil }
                return entry
            }
            .sorted { ($0.wakeTime ?? $0.date) < ($1.wakeTime ?? $1.date) }
            .suffix(7)
            .map { entry in
                let wakeTime = entry.wakeTime ?? entry.date
                let components = calendar.dateComponents([.hour, .minute], from: wakeTime)
                let minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)

                return WakeHistoryPoint(
                    id: "wake-\(Int(wakeTime.timeIntervalSince1970))",
                    date: entry.date,
                    wakeTime: wakeTime,
                    label: calendar.isDateInToday(wakeTime) ? "Today" : entry.dayLabel,
                    minuteOfDay: minuteOfDay
                )
            }

        let samplePoints = SleepHistoryStore.shared
            .wakeTimeSamples(since: cutoff, through: referenceDate)
            .filter { sample in
                !entryPoints.contains { calendar.isDate($0.wakeTime, inSameDayAs: sample) }
            }
            .map { wakeTime in
                let components = calendar.dateComponents([.hour, .minute], from: wakeTime)
                let minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)

                return WakeHistoryPoint(
                    id: "wake-sample-\(Int(wakeTime.timeIntervalSince1970))",
                    date: wakeTime,
                    wakeTime: wakeTime,
                    label: calendar.isDateInToday(wakeTime) ? "Today" : Self.dayLabel(for: wakeTime),
                    minuteOfDay: minuteOfDay
                )
            }

        return (entryPoints + samplePoints)
            .sorted { $0.wakeTime < $1.wakeTime }
            .suffix(7)
    }

    static func averageWakeTime(from points: [WakeHistoryPoint]) -> Date? {
        guard !points.isEmpty else { return nil }
        let averageMinute = points.reduce(0) { $0 + $1.minuteOfDay } / points.count
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = averageMinute / 60
        components.minute = averageMinute % 60
        return calendar.date(from: components)
    }

    private static func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

private struct WakeTimesCard: View {
    let points: [WakeHistoryPoint]
    let averageWakeTime: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("WAKE TIMES")
                        .font(.custom("DM Sans", size: 11))
                        .foregroundColor(Color.white.opacity(0.35))
                        .kerning(2.5)

                    if let averageWakeTime {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(timeLabel(averageWakeTime, includePeriod: false))
                                .font(.custom("Poppins-Medium", size: 38))
                                .foregroundColor(Color.white.opacity(0.96))

                            Text(periodLabel(averageWakeTime))
                                .font(.custom("DM Sans", size: 16).weight(.medium))
                                .foregroundColor(Color.white.opacity(0.52))
                                .padding(.bottom, 4)
                        }
                    }
                }

                Spacer()

                Text("average\nlast 7 days")
                    .font(.custom("DM Sans", size: 12))
                    .foregroundColor(Color.white.opacity(0.4))
                    .multilineTextAlignment(.trailing)
                    .lineSpacing(2)
            }

            if points.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sun.horizon")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundColor(Color.white.opacity(0.2))

                    Text("Wake times will appear here\nafter a few mornings")
                        .font(.custom("DM Sans", size: 13))
                        .foregroundColor(Color.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                WakeTimesChart(points: points)
                    .frame(height: 150)

                Text("Last 7 days")
                    .font(.custom("DM Sans", size: 12))
                    .foregroundColor(Color.white.opacity(0.34))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func timeLabel(_ date: Date, includePeriod: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        if includePeriod {
            return formatter.string(from: date)
        }

        formatter.dateFormat = "h:mm"
        return formatter.string(from: date)
    }

    private func periodLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
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
// WakeTimesChart
// ─────────────────────────────────────────────────────────────
// A simple last-seven-days wake-time line chart.

private struct WakeTimesChart: View {
    let points: [WakeHistoryPoint]

    private var axis: WakeTimeAxis {
        WakeTimeAxis(points: points)
    }

    var body: some View {
        GeometryReader { geo in
            let axisWidth: CGFloat = 38
            let axisSpacing: CGFloat = 8
            let xLabelHeight: CGFloat = 24
            let plotWidth = max(geo.size.width - axisWidth - axisSpacing, 1)
            let plotHeight = max(geo.size.height - xLabelHeight, 1)
            let coordinates = chartCoordinates(width: plotWidth, height: plotHeight)

            HStack(alignment: .top, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ForEach(axis.tickMinutes, id: \.self) { minute in
                        Text(axis.label(for: minute))
                            .font(.custom("DM Sans", size: 10))
                            .foregroundColor(Color.white.opacity(0.38))
                            .position(x: axisWidth / 2, y: yPosition(for: minute, height: plotHeight))
                    }
                }
                .frame(width: axisWidth, height: plotHeight)

                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        ForEach(axis.tickMinutes, id: \.self) { minute in
                            Rectangle()
                                .fill(Color.white.opacity(0.075))
                                .frame(width: plotWidth, height: 1)
                                .position(x: plotWidth / 2, y: yPosition(for: minute, height: plotHeight))
                            }

                        Path { path in
                            guard let first = coordinates.first else { return }
                            path.move(to: first)
                            for coordinate in coordinates.dropFirst() {
                                path.addLine(to: coordinate)
                            }
                        }
                        .stroke(
                            Color.white.opacity(0.55),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 8])
                        )

                        ForEach(Array(zip(points, coordinates)), id: \.0.id) { _, coordinate in
                            Circle()
                                .fill(Color.white)
                                .frame(width: 9, height: 9)
                                .position(coordinate)
                        }
                    }
                    .frame(width: plotWidth, height: plotHeight)

                    HStack(spacing: 0) {
                        ForEach(points) { point in
                            Text(point.label)
                                .font(.custom("DM Sans", size: 11))
                                .foregroundColor(Color.white.opacity(0.4))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(width: plotWidth, height: xLabelHeight)
                }
            }
        }
    }

    private func yPosition(for minute: Int, height: CGFloat) -> CGFloat {
        let range = max(axis.maxMinute - axis.minMinute, 1)
        let normalized = CGFloat(minute - axis.minMinute) / CGFloat(range)
        return height - (normalized * height)
    }

    private func chartCoordinates(width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let xStep = points.count == 1 ? 0 : width / CGFloat(points.count - 1)
        let range = max(axis.maxMinute - axis.minMinute, 1)

        return points.enumerated().map { index, point in
            let x = points.count == 1 ? width / 2 : CGFloat(index) * xStep
            let normalized = CGFloat(point.minuteOfDay - axis.minMinute) / CGFloat(range)
            let y = height - (normalized * height)
            return CGPoint(x: x, y: y)
        }
    }
}

private struct WakeTimeAxis {
    let minMinute: Int
    let maxMinute: Int
    let tickMinutes: [Int]

    init(points: [WakeHistoryPoint]) {
        let values = points.map(\.minuteOfDay)
        let minValue = values.min() ?? 6 * 60
        let maxValue = values.max() ?? 9 * 60
        var lower = (minValue / 60) * 60
        var upper = Int(ceil(Double(maxValue) / 60.0)) * 60

        if upper - lower < 3 * 60 {
            let midpoint = (lower + upper) / 2
            lower = max(0, midpoint - 90)
            upper = min(24 * 60, lower + 3 * 60)
            lower = max(0, upper - 3 * 60)
        }

        minMinute = lower
        maxMinute = upper
        let step = max((upper - lower) / 3, 60)
        tickMinutes = stride(from: upper, through: lower, by: -step).map { $0 }
    }

    func label(for minute: Int) -> String {
        let hour24 = (minute / 60) % 24
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let period = hour24 < 12 ? "AM" : "PM"
        return "\(hour12) \(period)"
    }
}

#Preview("Sleep Insights — no wearable") {
    @Previewable @State var answers: SurveyAnswers = {
        var a = SurveyAnswers()
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

#Preview("Wake Times Chart — mock data") {
    let points = WakeHistoryPoint.points(from: SleepHistoryMock.entries, referenceDate: Date())

    ZStack {
        Color(red: 0.07, green: 0.04, blue: 0.15).ignoresSafeArea()
        WakeTimesChart(points: points)
        .frame(height: 200)
        .padding(.horizontal, 24)
    }
}
