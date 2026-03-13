import SwiftUI

// ── MARK: Dashboard ──────────────────────────────────────────

struct LuniferDashboard: View {
    @Binding var answers: SurveyAnswers
    @State private var showSettings = false

    private var wakeUpTime: String {
        let targetMinutes = 9 * 60
        let routineMinutes = answers.routine.auto
            ? 60
            : answers.routine.hours * 60 + answers.routine.minutes
        let commuteMinutes: Int
        if answers.lifestyle == "student" || answers.lifestyle == "commuter" {
            commuteMinutes = answers.commute.auto ? 30 : answers.commute.hours * 60 + answers.commute.minutes
        } else {
            commuteMinutes = 0
        }
        let wakeMinutes = ((targetMinutes - routineMinutes - commuteMinutes) % (24 * 60) + 24 * 60) % (24 * 60)
        let hour    = wakeMinutes / 60
        let minute  = wakeMinutes % 60
        let period  = hour >= 12 ? "PM" : "AM"
        let display = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return String(format: "%d:%02d %@", display, minute, period)
    }

    private var tomorrowDateString: String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: tomorrow)
    }

    var body: some View {
        ZStack {
            LuniferBackground()

            VStack(spacing: 0) {

                // ── Settings button ───────────────────────────
                HStack {
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.85))
                            .padding(14)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                            )
                            .padding(20)
                            .padding(.horizontal, 16)
                    }
                }

                Spacer()

                // ── Wake-up time ──────────────────────────────
                VStack(spacing: 12) {
                    Text("TOMORROW'S ALARM")
                        .font(.custom("DM Sans", size: 11))
                        .foregroundColor(Color.white.opacity(0.35))
                        .kerning(2.5)

                    Text(wakeUpTime)
                        .font(.custom("Cormorant Garamond", size: 68).weight(.light))
                        .foregroundColor(Color.white.opacity(0.95))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    Text(tomorrowDateString)
                        .font(.custom("DM Sans", size: 14))
                        .foregroundColor(Color.white.opacity(0.3))
                }

                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSettings) {
            LuniferSettings(answers: $answers)
        }
    }
}

// ── MARK: Settings ────────────────────────────────────────────

struct LuniferSettings: View {
    @Binding var answers: SurveyAnswers
    @Environment(\.dismiss) private var dismiss

    private var showCommute: Bool {
        answers.lifestyle == "student" || answers.lifestyle == "commuter"
    }

    var body: some View {
        ZStack {
            Color.luniferBg.ignoresSafeArea()
            StarsView()

            VStack(spacing: 0) {

                // ── Header ────────────────────────────────────
                HStack {
                    Text("Settings")
                        .font(.custom("Cormorant Garamond", size: 28).weight(.light))
                        .foregroundColor(Color.white.opacity(0.9))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(Color.white.opacity(0.45))
                            .padding(10)
                            .background(Circle().fill(Color.white.opacity(0.07)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {

                        // ── About You (collapsible) ───────────
                        CollapsibleSection(title: "About You") {
                            VStack(spacing: 24) {

                                SettingsSection(title: "Age") {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.white.opacity(0.03))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .stroke(Color.white.opacity(0.08), lineWidth: 1.5)
                                            )
                                        Picker("Age", selection: Binding(
                                            get: { Int(answers.age) ?? 18 },
                                            set: { answers.age = String($0) }
                                        )) {
                                            ForEach(1...125, id: \.self) { age in
                                                Text("\(age)").tag(age)
                                            }
                                        }
                                        .pickerStyle(.wheel)
                                        .colorScheme(.dark)
                                        .frame(height: 120)
                                        .clipped()
                                    }
                                    .frame(height: 120)
                                }

                                SettingsSection(title: "Lifestyle") {
                                    VStack(spacing: 8) {
                                        ForEach([
                                            ("student",     "I am a student"),
                                            ("wfh",         "I work from home"),
                                            ("commuter",    "I commute to work sometimes or most days"),
                                            ("not_working", "I'm not working right now"),
                                        ], id: \.0) { id, label in
                                            OptionCard(isSelected: answers.lifestyle == id) {
                                                answers.lifestyle = id
                                            } content: {
                                                Text(label)
                                                    .font(.custom("DM Sans", size: 14))
                                                    .foregroundColor(answers.lifestyle == id
                                                                     ? Color.white.opacity(0.95)
                                                                     : Color.white.opacity(0.7))
                                            }
                                        }
                                    }
                                }

                                SettingsSection(title: "Calendar") {
                                    VStack(spacing: 8) {
                                        ForEach([
                                            ("apple",   "Apple Calendar"),
                                            ("google",  "Google Calendar"),
                                            ("outlook", "Outlook"),
                                            ("none",    "I don't use one"),
                                        ], id: \.0) { id, label in
                                            OptionCard(isSelected: answers.calendar == id) {
                                                answers.calendar = id
                                            } content: {
                                                Text(label)
                                                    .font(.custom("DM Sans", size: 14))
                                                    .foregroundColor(answers.calendar == id
                                                                     ? Color.white.opacity(0.95)
                                                                     : Color.white.opacity(0.7))
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── Sleep ─────────────────────────────
                        SettingsSection(title: "Sleep Duration") {
                            TimeScalePicker(value: $answers.sleep,
                                            autoLabel: "I'm not sure — let Lunifer learn this")
                        }

                        // ── Morning Routine ───────────────────
                        SettingsSection(title: "Morning Routine") {
                            TimeScalePicker(value: $answers.routine,
                                            autoLabel: "Not sure — let Lunifer figure this out")
                        }

                        // ── Commute ───────────────────────────
                        if showCommute {
                            SettingsSection(title: "Commute") {
                                TimeScalePicker(value: $answers.commute,
                                                autoLabel: "Let Lunifer calculate this from my location")
                            }
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ── MARK: Collapsible section ─────────────────────────────────

private struct CollapsibleSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.3)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(title.uppercased())
                        .font(.custom("DM Sans", size: 11))
                        .foregroundColor(Color.white.opacity(0.35))
                        .kerning(2)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.35))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.3), value: expanded)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1.5)
                        )
                )
            }
            .buttonStyle(.plain)

            // Expandable content
            if expanded {
                VStack(alignment: .leading, spacing: 24) {
                    content()
                }
                .padding(.top, 20)
                .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
    }
}

// ── MARK: Settings section wrapper ───────────────────────────

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.custom("DM Sans", size: 11))
                .foregroundColor(Color.white.opacity(0.35))
                .kerning(2)
            content()
        }
    }
}

// ── MARK: Preview ─────────────────────────────────────────────

#Preview {
    LuniferDashboard(answers: .constant(SurveyAnswers()))
}
