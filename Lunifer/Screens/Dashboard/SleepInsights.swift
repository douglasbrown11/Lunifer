import SwiftUI

// ─────────────────────────────────────────────────────────────
// SleepInsights
// ─────────────────────────────────────────────────────────────
// Accessible by swiping right from the dashboard.
// Shows:
//   1. Recommended optimal sleep duration (top)
//   2. 7-day sleep history bar chart (below)

struct SleepInsights: View {
    @Binding var answers: SurveyAnswers

    /// Injected entries for SwiftUI previews. Nil in production — falls back to the live store.
    var previewEntries: [SleepHistoryEntry]? = nil

    @State private var showChangeSheet = false
    @State private var showWearableWarning = false
    /// Local copy edited inside the sheet; committed on save.
    @State private var draftSleep = TimeValue(hours: 8, minutes: 0, auto: false)

    // Wearable state — read directly from AppStorage so changes sync immediately
    @AppStorage("whoopConnected")             private var whoopConnected: Bool   = false
    @AppStorage("whoopRecommendedSleepHours") private var whoopSleepHours: Double = 0
    @AppStorage("ouraConnected")              private var ouraConnected: Bool    = false
    @AppStorage("ouraRecommendedSleepHours")  private var ouraSleepHours: Double  = 0

    // Pull sleep history from the manager (or injected preview data)
    private var history: [SleepHistoryEntry] {
        previewEntries ?? SleepHistoryManager.shared.recentHistory(days: 7)
    }

    // Priority: WHOOP > Oura > manual preference > age baseline
    private var recommendedHours: Double {
        if whoopConnected && whoopSleepHours > 0 {
            return whoopSleepHours
        } else if ouraConnected && ouraSleepHours > 0 {
            return ouraSleepHours
        } else if answers.sleep.auto {
            return SleepDurationModel.baselineForAge(answers.age)
        } else {
            return Double(answers.sleep.hours) + Double(answers.sleep.minutes) / 60.0
        }
    }

    private var isWhoopDriven: Bool { whoopConnected && whoopSleepHours > 0 }
    private var isOuraDriven:  Bool { !isWhoopDriven && ouraConnected && ouraSleepHours > 0 }

    var body: some View {
        VStack(spacing: 0) {

                Spacer().frame(height: 60)

                // ── Optimal sleep duration card ──────────
                VStack(spacing: 16) {

                    // "change" sits in the top-left corner of the card
                    HStack {
                        Button {
                            draftSleep = answers.sleep
                            if isWhoopDriven || isOuraDriven {
                                showWearableWarning = true
                            } else {
                                showChangeSheet = true
                            }
                        } label: {
                            Text("change")
                                .font(.custom("DM Sans", size: 18))
                                .foregroundColor(Color.white.opacity(0.95))
                        }
                        .buttonStyle(.plain)
                        .alert("Override wearable recommendation?", isPresented: $showWearableWarning) {
                            Button("Set Manually", role: .destructive) {
                                showChangeSheet = true
                            }
                            Button("Keep Recommendation", role: .cancel) { }
                        } message: {
                            Text("Your sleep goal was set by your \(isWhoopDriven ? "WHOOP" : "Oura Ring"). Setting it manually will replace that recommendation.")
                        }
                        Spacer()
                    }

                    Text("SLEEP")
                        .font(.custom("DM Sans", size: 11))
                        .foregroundColor(Color.white.opacity(0.35))
                        .kerning(2.5)

                    Text(SleepDurationModel.formatted(recommendedHours))
                        .font(.custom("Libre Franklin", size: 51).weight(.light))
                        .foregroundColor(Color.white.opacity(0.95))

                    // "recommended to you via [logo]" — or plain text if no wearable
                    if isWhoopDriven {
                        HStack(spacing: 6) {
                            Text("recommended to you via")
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(Color.white.opacity(0.4))
                            Image("WhoopLogo")
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(height: 14)
                        }
                        .transition(.opacity)
                    } else if isOuraDriven {
                        HStack(spacing: 6) {
                            Text("recommended to you via")
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(Color.white.opacity(0.4))
                            ZStack {
                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 16, height: 16)
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 1.5)
                                    .frame(width: 12, height: 12)
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 0.8)
                                    .frame(width: 6, height: 6)
                            }
                            Text("Oura Ring")
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(Color.white.opacity(0.4))
                        }
                        .transition(.opacity)
                    } else {
                        Text("recommended for you")
                            .font(.custom("DM Sans", size: 14))
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)

                Spacer().frame(height: 36)

                // ── 7-day history chart ──────────────────
                Text("LAST 7 DAYS")
                    .font(.custom("DM Sans", size: 11))
                    .foregroundColor(Color.white.opacity(0.35))
                    .kerning(2.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                Group {
                    if history.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "moon.zzz")
                                .font(.system(size: 32, weight: .ultraLight))
                                .foregroundColor(Color.white.opacity(0.2))

                            Text("Sleep data will appear here\nafter your first night")
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(Color.white.opacity(0.3))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        SleepHistoryChart(
                            entries: history,
                            recommendedHours: recommendedHours
                        )
                        .frame(height: 180)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
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
                .padding(.horizontal, 20)

                Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            WhoopManager.shared.refreshIfNeeded()
            OuraManager.shared.refreshIfNeeded()
        }
        // ── Edit sleep sheet ─────────────────────────────
        .sheet(isPresented: $showChangeSheet) {
            SleepEditSheet(sleep: $draftSleep) {
                // Save callback
                answers.sleep = draftSleep
                answers.saveToDefaults()
                answers.saveToFirestore()
                showChangeSheet = false
            }
            .presentationDetents([.fraction(0.52)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(red: 0.07, green: 0.04, blue: 0.15))
        }
    }
}

// ─────────────────────────────────────────────────────────────
// SleepEditSheet after clicking "change"
// ─────────────────────────────────────────────────────────────

private struct SleepEditSheet: View {
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
                            autoLabel: "I'm not sure — let Lunifer learn this")
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
// A bar chart showing sleep duration for each of the last 7
// nights, with a dashed recommended-hours line, compact
// duration labels above each bar, a clean X-axis divider, and
// weekday labels below (with "Today" highlighted in purple).

struct SleepHistoryChart: View {
    let entries: [SleepHistoryEntry]
    let recommendedHours: Double

    /// Oldest → newest so the chart reads left-to-right chronologically.
    private var sortedEntries: [SleepHistoryEntry] {
        entries.sorted { $0.date < $1.date }
    }

    private var maxHours: Double {
        let tallest = entries.map(\.durationHours).max() ?? 8
        return max(tallest + 1, 10)
    }

    var body: some View {
        GeometryReader { geo in
            let count      = max(sortedEntries.count, 1)
            let spacing    = CGFloat(8)
            let barWidth   = min((geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count), 44)

            // Vertical layout constants
            let durLabelH  = CGFloat(16)   // compact "8:30" label above each bar
            let axisH      = CGFloat(1)    // X-axis divider line
            let xLabelH    = CGFloat(22)   // weekday label row
            let barAreaH   = geo.size.height - axisH - xLabelH
            let barSlotH   = barAreaH - durLabelH  // pure bar space (below duration labels)

            VStack(spacing: 0) {

                // ── Bar + duration-label area ────────────────
                ZStack(alignment: .bottom) {

                    // Bar columns
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(sortedEntries) { entry in
                            let barH      = max(barSlotH * (entry.durationHours / maxHours), 4)
                            let meetsGoal = entry.durationHours >= recommendedHours

                            VStack(spacing: 4) {
                                // Compact duration label: "8:30"
                                Text(SleepDurationModel.shortFormatted(entry.durationHours))
                                    .font(.custom("DM Sans", size: 10))
                                    .foregroundColor(Color.white.opacity(0.45))
                                    .frame(height: durLabelH)

                                // Bar
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        meetsGoal
                                        ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.6)
                                        : Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.25)
                                    )
                                    .frame(width: barWidth, height: barH)
                            }
                            .frame(width: barWidth)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: barAreaH)

                // ── X-axis divider ───────────────────────────
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: axisH)

                // ── Weekday labels ───────────────────────────
                HStack(spacing: spacing) {
                    ForEach(sortedEntries) { entry in
                        let isToday = Calendar.current.isDateInToday(entry.date)
                        Text(isToday ? "Today" : entry.dayLabel)
                            .font(.custom("DM Sans", size: 11))
                            .foregroundColor(
                                isToday
                                ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.85)
                                : Color.white.opacity(0.4)
                            )
                            .frame(width: barWidth)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 5)
                .frame(height: xLabelH)
            }
        }
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
    ZStack {
        Color(red: 0.07, green: 0.04, blue: 0.15).ignoresSafeArea()
        SleepHistoryChart(
            entries: SleepHistoryMock.entries,
            recommendedHours: 8.0
        )
        .frame(height: 200)
        .padding(.horizontal, 24)
    }
}
