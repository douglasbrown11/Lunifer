import SwiftUI
import FirebaseAuth

// ── MARK: Settings (root) ─────────────────────────────────────

struct LuniferSettings: View {
    @Binding var answers: SurveyAnswers
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
                            NavigationLink {
                                AboutYouSettingsView(answers: $answers)
                            } label: {
                                settingsNavRow(title: "About You")
                            }

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
            }
            Button("No", role: .cancel) { }
        }
    }
}

// ── MARK: About You ────────────────────────────────────────────

struct AboutYouSettingsView: View {
    @Binding var answers: SurveyAnswers
    @Environment(\.dismiss) private var dismiss
    @State private var editingField: String? = nil

    private var lifestyleLabel: String {
        switch answers.lifestyle {
        case "student": return "Student"
        case "commuter": return "Commuter"
        case "wfh": return "Work From Home"
        case "not_working": return "Not Working"
        default: return "Not set"
        }
    }

    private var calendarLabel: String {
        switch answers.calendar {
        case "apple": return "Apple Calendar"
        case "google": return "Google Calendar"
        case "outlook": return "Outlook"
        case "none": return "None"
        default: return "Not set"
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.luniferBg.ignoresSafeArea()
            StarsView()

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(Color.white.opacity(0.75))
                            .frame(width: 36, height: 36)
                    }
                    Spacer()
                    Text("About you")
                        .font(.custom("Cormorant Garamond", size: 28).weight(.light))
                        .foregroundColor(Color.white.opacity(0.9))
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        aboutYouRow(label: "Age", value: answers.age, field: "age")
                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.leading, 16)
                        aboutYouRow(label: "Lifestyle", value: lifestyleLabel, field: "lifestyle")
                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.leading, 16)
                        aboutYouRow(label: "Calendar", value: calendarLabel, field: "calendar")
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: answers.age) { _, _ in
            answers.saveToDefaults()
        }
        .onChange(of: answers.lifestyle) { _, _ in
            answers.saveToDefaults()
        }
        .onChange(of: answers.calendar) { _, _ in
            answers.saveToDefaults()
        }
    }

    @ViewBuilder
    private func aboutYouRow(label: String, value: String, field: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.custom("DM Sans", size: 14))
                    .foregroundColor(Color.white.opacity(0.45))

                Text(value)
                    .font(.custom("DM Sans", size: 14))
                    .foregroundColor(Color.white.opacity(0.85))
                    .padding(.leading, 12)

                Spacer()

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
                Divider()
                    .background(Color.white.opacity(0.06))

                Group {
                    switch field {
                    case "age":
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

                    case "lifestyle":
                        VStack(spacing: 8) {
                            ForEach([
                                ("student", "Student"),
                                ("commuter", "Commuter"),
                                ("wfh", "Work From Home"),
                                ("not_working", "Not Working")
                            ], id: \.0) { id, title in
                                Button {
                                    answers.lifestyle = id
                                } label: {
                                    HStack {
                                        Text(title)
                                            .font(.custom("DM Sans", size: 14))
                                            .foregroundColor(answers.lifestyle == id ? Color.white.opacity(0.95) : Color.white.opacity(0.7))
                                        Spacer()
                                        if answers.lifestyle == id {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0))
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.white.opacity(0.03))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(
                                                        answers.lifestyle == id
                                                        ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.55)
                                                        : Color.white.opacity(0.06),
                                                        lineWidth: 1
                                                    )
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                    case "calendar":
                        VStack(spacing: 8) {
                            ForEach([
                                ("apple", "Apple Calendar"),
                                ("google", "Google Calendar"),
                                ("outlook", "Outlook"),
                                ("none", "None")
                            ], id: \.0) { id, title in
                                Button {
                                    answers.calendar = id
                                } label: {
                                    HStack {
                                        Text(title)
                                            .font(.custom("DM Sans", size: 14))
                                            .foregroundColor(answers.calendar == id ? Color.white.opacity(0.95) : Color.white.opacity(0.7))
                                        Spacer()
                                        if answers.calendar == id {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0))
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.white.opacity(0.03))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(
                                                        answers.calendar == id
                                                        ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.55)
                                                        : Color.white.opacity(0.06),
                                                        lineWidth: 1
                                                    )
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
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
    .background(
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    )
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

// ── MARK: Preview ─────────────────────────────────────────────

#Preview {
    LuniferSettings(answers: .constant({
        var answers = SurveyAnswers()
        answers.age = "21"
        answers.lifestyle = "commuter"
        return answers
    }()))
}
