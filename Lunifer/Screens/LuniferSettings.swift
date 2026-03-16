import SwiftUI
import FirebaseAuth

// ── MARK: Settings (root) ─────────────────────────────────────

struct LuniferSettings: View {
    @Binding var answers: SurveyAnswers
    var onSignOut: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @AppStorage("snoozeMinutes") private var snoozeMinutes: Int = 5
    @AppStorage("surveyCompleted") private var surveyCompleted = false
    @State private var showSignOutAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.luniferBg.ignoresSafeArea()
                StarsView()

                VStack(spacing: 0) {
                    // ── Header ────────────────────────────────
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
                        VStack(spacing: 24) {

                            // ── Nav rows ──────────────────────
                            VStack(spacing: 0) {
                                NavigationLink {
                                    AboutYouSettingsView(answers: $answers)
                                } label: {
                                    settingsNavRow(title: "About You")
                                }
                                Divider()
                                    .background(Color.white.opacity(0.06))
                                    .padding(.leading, 16)
                                NavigationLink {
                                    SleepSettingsView(answers: $answers)
                                } label: {
                                    settingsNavRow(title: "Sleep")
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.04))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                            )

                            // ── Snooze inline ─────────────────
                            SettingsSection(title: "Snooze Time") {
                                VStack(spacing: 12) {
                                    HStack {
                                        Spacer()
                                        Text("\(snoozeMinutes) min")
                                            .font(.custom("DM Sans", size: 14))
                                            .foregroundColor(Color(red: 0.706, green: 0.588, blue: 0.902))
                                            .monospacedDigit()
                                    }
                                    Slider(value: Binding(
                                        get: { Double(snoozeMinutes) },
                                        set: { snoozeMinutes = Int($0.rounded()) }
                                    ), in: 1...30, step: 1)
                                    .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
                                    HStack {
                                        Text("1 min")
                                        Spacer()
                                        Text("30 min")
                                    }
                                    .font(.custom("DM Sans", size: 11))
                                    .foregroundColor(Color.white.opacity(0.2))
                                }
                            }

                            // ── Sign out ──────────────────────
                            Button {
                                showSignOutAlert = true
                            } label: {
                                Text("Sign Out")
                                    .font(.custom("DM Sans", size: 14))
                                    .foregroundColor(Color.red.opacity(0.8))
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }

                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .alert("Are you sure you want to sign out?", isPresented: $showSignOutAlert) {
            Button("Yes", role: .destructive) {
                try? Auth.auth().signOut()
                surveyCompleted = false
                UserDefaults.standard.removeObject(forKey: "surveyAnswers")
                dismiss()
                onSignOut?()
            }
            Button("No", role: .cancel) { }
        }
    }
}

// ── MARK: About You detail ────────────────────────────────────

struct AboutYouSettingsView: View {
    @Binding var answers: SurveyAnswers
    @Environment(\.dismiss) private var dismiss
    @State private var editingField: String? = nil

    private var lifestyleLabel: String {
        switch answers.lifestyle {
        case "student":     return "Student"
        case "wfh":         return "Work from home"
        case "commuter":    return "Commuter"
        case "not_working": return "Not working"
        default:            return "Not set"
        }
    }

    private var calendarLabel: String {
        switch answers.calendar {
        case "apple":   return "Apple Calendar"
        case "google":  return "Google Calendar"
        case "outlook": return "Outlook"
        case "none":    return "None"
        default:        return "Not set"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .light))
                        Text("Settings")
                            .font(.custom("DM Sans", size: 14))
                    }
                    .foregroundColor(Color.white.opacity(0.45))
                }
                Spacer()
                Text("About You")
                    .font(.custom("Cormorant Garamond", size: 24).weight(.light))
                    .foregroundColor(Color.white.opacity(0.9))
                Spacer()
                Color.clear.frame(width: 80)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    memoryLogRow(label: "Age", value: answers.age, field: "age")
                    Divider().background(Color.white.opacity(0.08)).padding(.leading, 16)
                    memoryLogRow(label: "Lifestyle", value: lifestyleLabel, field: "lifestyle")
                    Divider().background(Color.white.opacity(0.08)).padding(.leading, 16)
                    memoryLogRow(label: "Calendar", value: calendarLabel, field: "calendar")
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                )
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            Color.luniferBg.ignoresSafeArea()
            StarsView()
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private func memoryLogRow(label: String, value: String, field: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.custom("DM Sans", size: 14))
                    .foregroundColor(Color.white.opacity(0.45))
                Spacer()
                Text(value)
                    .font(.custom("DM Sans", size: 14))
                    .foregroundColor(Color.white.opacity(0.85))
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        editingField = editingField == field ? nil : field
                    }
                } label: {
                    Text(editingField == field ? "Done" : "Change")
                        .font(.custom("DM Sans", size: 13))
                        .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0))
                }
                .padding(.leading, 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if editingField == field {
                Divider().background(Color.white.opacity(0.06))
                Group {
                    switch field {
                    case "age":
                        Picker("Age", selection: Binding(
                            get: { Int(answers.age) ?? 18 },
                            set: { answers.age = String($0) }
                        )) {
                            ForEach(1...125, id: \.self) { age in Text("\(age)").tag(age) }
                        }
                        .pickerStyle(.wheel)
                        .colorScheme(.dark)
                        .frame(height: 120)
                        .clipped()

                    case "lifestyle":
                        VStack(spacing: 8) {
                            ForEach([
                                ("student",     "I am a student"),
                                ("wfh",         "I work from home"),
                                ("commuter",    "I commute to work sometimes or most days"),
                                ("not_working", "I'm not working right now"),
                            ], id: \.0) { id, lbl in
                                OptionCard(isSelected: answers.lifestyle == id) {
                                    answers.lifestyle = id
                                } content: {
                                    Text(lbl)
                                        .font(.custom("DM Sans", size: 14))
                                        .foregroundColor(answers.lifestyle == id ? Color.white.opacity(0.95) : Color.white.opacity(0.7))
                                }
                            }
                        }

                    case "calendar":
                        VStack(spacing: 8) {
                            ForEach([
                                ("apple",   "Apple Calendar"),
                                ("google",  "Google Calendar"),
                                ("outlook", "Outlook"),
                                ("none",    "I don't use one"),
                            ], id: \.0) { id, lbl in
                                OptionCard(isSelected: answers.calendar == id) {
                                    answers.calendar = id
                                } content: {
                                    Text(lbl)
                                        .font(.custom("DM Sans", size: 14))
                                        .foregroundColor(answers.calendar == id ? Color.white.opacity(0.95) : Color.white.opacity(0.7))
                                }
                            }
                        }

                    default:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
    }
}

// ── MARK: Sleep detail ────────────────────────────────────────

struct SleepSettingsView: View {
    @Binding var answers: SurveyAnswers
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .light))
                        Text("Settings")
                            .font(.custom("DM Sans", size: 14))
                    }
                    .foregroundColor(Color.white.opacity(0.45))
                }
                Spacer()
                Text("Sleep")
                    .font(.custom("Cormorant Garamond", size: 24).weight(.light))
                    .foregroundColor(Color.white.opacity(0.9))
                Spacer()
                Color.clear.frame(width: 80)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    SettingsSection(title: "Optimal Sleep Duration") {
                        TimeScalePicker(value: $answers.sleep, autoLabel: "Let Lunifer learn this")
                    }
                    SettingsSection(title: "Morning Routine") {
                        TimeScalePicker(value: $answers.routine, autoLabel: "Let Lunifer figure this out")
                    }
                    SettingsSection(title: "Commute") {
                        TimeScalePicker(value: $answers.commute, autoLabel: "Let Lunifer calculate this from my location")
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            Color.luniferBg.ignoresSafeArea()
            StarsView()
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// ── MARK: Shared components ───────────────────────────────────

private func settingsNavRow(title: String) -> some View {
    HStack {
        Text(title)
            .font(.custom("DM Sans", size: 15))
            .foregroundColor(Color.white.opacity(0.85))
        Spacer()
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .light))
            .foregroundColor(Color.white.opacity(0.25))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 16)
}

struct SettingsSection<Content: View>: View {
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

// ── MARK: Previews ────────────────────────────────────────────

private var previewAnswers: SurveyAnswers {
    var a = SurveyAnswers()
    a.age       = "28"
    a.lifestyle = "commuter"
    a.calendar  = "apple"
    a.sleep     = TimeValue(hours: 8, minutes: 0,  auto: false)
    a.routine   = TimeValue(hours: 0, minutes: 45, auto: false)
    a.commute   = TimeValue(hours: 0, minutes: 30, auto: false)
    return a
}

#Preview("Settings") {
    LuniferSettings(answers: .constant(previewAnswers))
}

#Preview("About You") {
    NavigationStack {
        AboutYouSettingsView(answers: .constant(previewAnswers))
    }
}

#Preview("Sleep") {
    NavigationStack {
        SleepSettingsView(answers: .constant(previewAnswers))
    }
}
