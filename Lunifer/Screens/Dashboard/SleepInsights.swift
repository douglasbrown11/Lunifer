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

    @State private var showChangeSheet = false
    /// Local copy edited inside the sheet; committed on save.
    @State private var draftSleep = TimeValue(hours: 8, minutes: 0, auto: false)

    // Wearable state — read directly from AppStorage so changes sync immediately
    @AppStorage("whoopConnected")             private var whoopConnected: Bool   = false
    @AppStorage("whoopRecommendedSleepHours") private var whoopSleepHours: Double = 0
    @AppStorage("ouraConnected")              private var ouraConnected: Bool    = false
    @AppStorage("ouraRecommendedSleepHours")  private var ouraSleepHours: Double  = 0

    // Pull sleep history from the manager
    private var history: [SleepHistoryEntry] {
        SleepHistoryManager.shared.recentHistory(days: 7)
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
                            showChangeSheet = true
                        } label: {
                            Text("change")
                                .font(.custom("DM Sans", size: 18))
                                .foregroundColor(Color.white.opacity(0.95))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        
                    }

                    Text("SLEEP")
                        .font(.custom("DM Sans", size: 11))
                        .foregroundColor(Color.white.opacity(0.35))
                        .kerning(2.5)

                    Text(SleepDurationModel.formatted(recommendedHours))
                        .font(.custom("Libre Franklin", size: 51).weight(.light))
                        .foregroundColor(Color.white.opacity(0.95))

                    Text("recommended for you")
                        .font(.custom("DM Sans", size: 14))
                        .foregroundColor(Color.white.opacity(0.4))

                    // Wearable attribution badge
                    if isWhoopDriven {
                        HStack(spacing: 6) {
                            Image("WhoopLogo")
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 18, height: 18)
                            Text("via WHOOP")
                                .font(.custom("DM Sans", size: 12))
                                .foregroundColor(Color.white.opacity(0.45))
                        }
                        .transition(.opacity)
                    } else if isOuraDriven {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 18, height: 18)
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 1.5)
                                    .frame(width: 13, height: 13)
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 0.8)
                                    .frame(width: 7, height: 7)
                            }
                            Text("via Oura Ring")
                                .font(.custom("DM Sans", size: 12))
                                .foregroundColor(Color.white.opacity(0.45))
                        }
                        .transition(.opacity)
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
                .padding(.horizontal, 75)

                Spacer().frame(height: 36)

                // ── 7-day history chart ──────────────────
                Text("LAST 7 DAYS")
                    .font(.custom("DM Sans", size: 11))
                    .foregroundColor(Color.white.opacity(0.35))
                    .kerning(2.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 65)
                    .padding(.bottom, 16)

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
                    .padding(.horizontal, 24)
                }

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
// A simple bar chart showing sleep duration for each of the
// last 7 nights, with a dashed line at the recommended level.

struct SleepHistoryChart: View {
    let entries: [SleepHistoryEntry]
    let recommendedHours: Double

    private var maxHours: Double { //used to set scale of Y-axis
        let tallest = entries.map(\.durationHours).max() ?? 8
        return max(tallest + 1, 10)
    }

    var body: some View {
        GeometryReader { geo in
            // Cap bar width so a single entry doesn't stretch edge-to-edge
            let barWidth: CGFloat = min(geo.size.width / CGFloat(max(entries.count, 1)) - 12, 44)
            let chartHeight = geo.size.height - 28  // leave room for labels

            ZStack(alignment: .bottom) {

                // ── Recommended line ─────────────────────────
                let lineY = chartHeight * (1 - recommendedHours / maxHours)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: lineY))
                    path.addLine(to: CGPoint(x: geo.size.width, y: lineY))
                }
                .stroke(
                    Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.4),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )

                // Recommended label
                Text("\(SleepDurationModel.formatted(recommendedHours))")
                    .font(.custom("DM Sans", size: 10))
                    .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.6))
                    .position(x: geo.size.width - 28, y: lineY - 10)

                // ── Bars ─────────────────────────────────────
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(entries) { entry in
                        VStack(spacing: 4) {
                            // Duration label above bar
                            Text(entry.formattedDuration)
                                .font(.custom("DM Sans", size: 10))
                                .foregroundColor(Color.white.opacity(0.5))

                            // Bar
                            let barHeight = max(chartHeight * (entry.durationHours / maxHours), 4)
                            let meetsGoal = entry.durationHours >= recommendedHours

                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    meetsGoal
                                    ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.6)
                                    : Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.25)
                                )
                                .frame(width: barWidth, height: barHeight)

                            // Day label below bar
                            Text(entry.dayLabel)
                                .font(.custom("DM Sans", size: 11))
                                .foregroundColor(Color.white.opacity(0.4))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview {
    @Previewable @State var answers: SurveyAnswers = {
        var a = SurveyAnswers()
        a.age = "22"
        return a
    }()
    SleepInsights(answers: $answers)
}
