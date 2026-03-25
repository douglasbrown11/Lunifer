import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn

// ── MARK: Settings (root) ─────────────────────────────────────

struct LuniferSettings: View {
    @Binding var answers: SurveyAnswers
    @Environment(\.dismiss) private var dismiss
    @AppStorage("snoozeMinutes") private var snoozeMinutes: Int = 5
    @AppStorage("surveyCompleted") private var surveyCompleted = false
    @State private var showSignOutAlert = false
    @State private var showDeleteAlert = false
    @State private var isDeletingAccount = false
    @State private var showDeleteErrorAlert = false
    @State private var deleteErrorMessage = ""
    @State private var showPasswordPrompt = false
    @State private var reauthPassword = ""

    private var userEmail: String {
        Auth.auth().currentUser?.email ?? "—"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.luniferBg.ignoresSafeArea()


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
                        VStack(spacing: 12) {
                            NavigationLink {
                                AboutYouSettingsView(answers: $answers)
                            } label: {
                                settingsNavRow(title: "About You")
                            }

                            NavigationLink {
                                NotificationsSettingsView()
                            } label: {
                                settingsNavRow(title: "Notifications")
                            }

                            NavigationLink {
                                WakeDaysSettingsView(answers: $answers)
                            } label: {
                                settingsNavRow(title: "Wake Days")
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

                            // ── Account ───────────────────────
                            SettingsSection(title: "Account") {
                                VStack(spacing: 0) {
                                    HStack(spacing: 10) {
                                        Text("Email")
                                            .font(.custom("DM Sans", size: 14))
                                            .foregroundColor(Color.white.opacity(0.45))
                                        Text(userEmail)
                                            .font(.custom("DM Sans", size: 14))
                                            .foregroundColor(Color.white.opacity(0.6))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.04))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                        )
                                )
                            }

                            // ── Sign out / Delete ─────────────
                            VStack(spacing: 12) {
                                Button {
                                    showSignOutAlert = true
                                } label: {
                                    Text("Sign Out")
                                        .font(.custom("DM Sans", size: 14))
                                        .foregroundColor(Color.white.opacity(0.55))
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.04))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                                )
                                        )
                                }
                                .alert("Are you sure you want to sign out?", isPresented: $showSignOutAlert) {
                                    Button("Yes", role: .destructive) {
                                        try? Auth.auth().signOut()
                                        dismiss()
                                    }
                                    Button("No", role: .cancel) { }
                                }

                                Button {
                                    showDeleteAlert = true
                                } label: {
                                    if isDeletingAccount {
                                        ProgressView()
                                            .tint(Color.red.opacity(0.7))
                                            .frame(maxWidth: .infinity, alignment: .center)
                                            .padding(.vertical, 14)
                                    } else {
                                        Text("Delete Account")
                                            .font(.custom("DM Sans", size: 14))
                                            .foregroundColor(Color.red.opacity(0.75))
                                            .frame(maxWidth: .infinity, alignment: .center)
                                            .padding(.vertical, 14)
                                    }
                                }
                                .disabled(isDeletingAccount)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.red.opacity(0.04))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.red.opacity(0.15), lineWidth: 1)
                                        )
                                )
                                .alert("Delete Account", isPresented: $showDeleteAlert) {
                                    Button("Delete", role: .destructive) {
                                        Task { await startDeletion() }
                                    }
                                    Button("Cancel", role: .cancel) { }
                                } message: {
                                    Text("This will permanently delete your account and all your data. This cannot be undone.")
                                }
                                .alert("Enter your password to confirm", isPresented: $showPasswordPrompt) {
                                    SecureField("Password", text: $reauthPassword)
                                    Button("Delete Account", role: .destructive) {
                                        Task { await reauthenticateAndDelete(password: reauthPassword) }
                                    }
                                    Button("Cancel", role: .cancel) { reauthPassword = ""; isDeletingAccount = false }
                                } message: {
                                    Text("For security, please re-enter your password to delete your account.")
                                }
                                .alert("Couldn't Delete Account", isPresented: $showDeleteErrorAlert) {
                                    Button("OK", role: .cancel) { }
                                } message: {
                                    Text(deleteErrorMessage)
                                }
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
    }

    // ── Account deletion ──────────────────────────────────────────
    // Step 1: Determine auth provider and reauthenticate before deleting.
    // Step 2: Delete Auth account first (requires recent login), then
    //         Firestore data, then clear local storage.

    /// Determines how the user signed in and triggers the appropriate
    /// reauthentication flow before deletion.
    private func startDeletion() async {
        guard let user = Auth.auth().currentUser else {
            deleteErrorMessage = "No signed-in user found. Please sign in and try again."
            showDeleteErrorAlert = true
            return
        }
        isDeletingAccount = true

        let providers = user.providerData.map { $0.providerID }

        if providers.contains("google.com") {
            // Google users: reauthenticate via Google Sign-In prompt
            await reauthenticateWithGoogle()
        } else {
            // Email/password users: show password prompt
            reauthPassword = ""
            showPasswordPrompt = true
        }
    }

    /// Reauthenticates an email/password user, then deletes.
    private func reauthenticateAndDelete(password: String) async {
        guard let user = Auth.auth().currentUser,
              let email = user.email else {
            isDeletingAccount = false
            deleteErrorMessage = "Unable to verify your account. Please try again."
            showDeleteErrorAlert = true
            return
        }

        do {
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            try await user.reauthenticate(with: credential)
            await performDeletion(user: user)
        } catch {
            isDeletingAccount = false
            reauthPassword = ""
            let nsError = error as NSError
            if nsError.code == AuthErrorCode.wrongPassword.rawValue {
                deleteErrorMessage = "Incorrect password. Please try again."
            } else {
                deleteErrorMessage = nsError.localizedDescription
            }
            showDeleteErrorAlert = true
            print("❌ Reauthentication failed: \(nsError.localizedDescription)")
        }
    }

    /// Reauthenticates a Google user via the Google Sign-In prompt, then deletes.
    private func reauthenticateWithGoogle() async {
        do {
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                  let window = windowScene.windows.first(where: { $0.isKeyWindow }),
                  let rootVC = window.rootViewController else {
                isDeletingAccount = false
                deleteErrorMessage = "Unable to present sign in. Please try again."
                showDeleteErrorAlert = true
                return
            }
            var presentingVC = rootVC
            while let presented = presentingVC.presentedViewController {
                presentingVC = presented
            }

            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC)
            guard let idToken = result.user.idToken?.tokenString else {
                isDeletingAccount = false
                deleteErrorMessage = "Something went wrong. Please try again."
                showDeleteErrorAlert = true
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            guard let user = Auth.auth().currentUser else {
                isDeletingAccount = false
                return
            }
            try await user.reauthenticate(with: credential)
            await performDeletion(user: user)
        } catch {
            isDeletingAccount = false
            let nsError = error as NSError
            // Google Sign-In cancellation
            if nsError.domain.contains("GIDSignIn") && nsError.code == -5 {
                return  // user cancelled, just reset silently
            }
            deleteErrorMessage = nsError.localizedDescription
            showDeleteErrorAlert = true
            print("❌ Google reauthentication failed: \(nsError.localizedDescription)")
        }
    }

    /// After successful reauthentication, deletes Firestore data first,
    /// then deletes the Auth account, then clears local storage.
    private func performDeletion(user: User) async {
        let db  = Firestore.firestore()
        let uid = user.uid
        let userDoc = db.collection("users").document(uid)

        do {
            // Delete Firestore data first so the UI promise of removing
            // account data is upheld before the auth account is removed.
            for sub in ["sleepHistory", "alarmInferences"] {
                let snap = try await userDoc.collection(sub).getDocuments()
                for doc in snap.documents {
                    try await doc.reference.delete()
                }
            }
            try await userDoc.delete()

            // Delete Firebase Auth account after cloud data cleanup succeeds.
            try await user.delete()

            // Clear local storage
            clearLocalAccountData()

            isDeletingAccount = false
            dismiss()
        } catch let nsError as NSError {
            isDeletingAccount = false
            deleteErrorMessage = nsError.localizedDescription
            showDeleteErrorAlert = true
            print("❌ Account deletion failed: \(nsError.localizedDescription)")
        }
    }

    private func clearLocalAccountData() {
        AccountDataManager.shared.clearLocalAccountData()
        surveyCompleted = false
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
            answers.saveToFirestore()
        }
        .onChange(of: answers.lifestyle) { _, _ in
            answers.saveToDefaults()
            answers.saveToFirestore()
        }
        .onChange(of: answers.calendar) { _, _ in
            answers.saveToDefaults()
            answers.saveToFirestore()
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

// ── MARK: Wake Days ────────────────────────────────────────────

struct WakeDaysSettingsView: View {
    @Binding var answers: SurveyAnswers
    @Environment(\.dismiss) private var dismiss

    private let days: [(id: String, label: String)] = [
        ("mon", "M"), ("tue", "T"), ("wed", "W"),
        ("thu", "T"), ("fri", "F"), ("sat", "S"), ("sun", "S")
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Color.luniferBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ────────────────────────────────
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(Color.white.opacity(0.75))
                            .frame(width: 36, height: 36)
                    }
                    Spacer()
                    Text("Wake Days")
                        .font(.custom("Cormorant Garamond", size: 28).weight(.light))
                        .foregroundColor(Color.white.opacity(0.9))
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)

                // ── Day buttons ───────────────────────────
                HStack(spacing: 10) {
                    ForEach(days, id: \.id) { day in
                        let selected = answers.wakeDays.contains(day.id)
                        Button {
                            toggleDay(day.id)
                        } label: {
                            Text(day.label)
                                .font(.custom("DM Sans", size: 15).weight(.medium))
                                .foregroundColor(selected
                                    ? Color.white.opacity(0.95)
                                    : Color.white.opacity(0.45))
                                .frame(width: 38, height: 38)
                                .background(
                                    Circle()
                                        .fill(selected
                                            ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.22)
                                            : Color.white.opacity(0.03))
                                        .overlay(
                                            Circle().stroke(
                                                selected
                                                    ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.75)
                                                    : Color.white.opacity(0.08),
                                                lineWidth: 1.5
                                            )
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if answers.wakeDays.isEmpty {
                    Text("Select at least one day.")
                        .font(.custom("DM Sans", size: 13))
                        .foregroundColor(Color.white.opacity(0.35))
                        .padding(.top, 16)
                }
            }
            .padding(.horizontal, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func toggleDay(_ day: String) {
        if answers.wakeDays.contains(day) {
            // Prevent deselecting the last day
            guard answers.wakeDays.count > 1 else { return }
            answers.wakeDays.removeAll { $0 == day }
        } else {
            answers.wakeDays.append(day)
            let order = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
            answers.wakeDays.sort { order.firstIndex(of: $0) ?? 0 < order.firstIndex(of: $1) ?? 0 }
        }
        answers.saveToDefaults()
        answers.saveToFirestore()
    }
}

// ── MARK: Notifications ────────────────────────────────────────

struct NotificationsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("batteryAlertEnabled") private var batteryAlertEnabled: Bool = true
    @AppStorage("wakeReminderEnabled") private var wakeReminderEnabled: Bool = true

    var body: some View {
        ZStack(alignment: .top) {
            Color.luniferBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ────────────────────────────────
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(Color.white.opacity(0.75))
                            .frame(width: 36, height: 36)
                    }
                    Spacer()
                    Text("Notifications")
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
                        // ── Battery alert row ─────────────
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Battery Alert")
                                    .font(.custom("DM Sans", size: 14))
                                    .foregroundColor(Color.white.opacity(0.85))
                                Text("Warn me if my phone won't survive until my alarm")
                                    .font(.custom("DM Sans", size: 12))
                                    .foregroundColor(Color.white.opacity(0.35))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Toggle("", isOn: $batteryAlertEnabled)
                                .labelsHidden()
                                .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)

                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.leading, 16)

                        // ── Alarm set alert row ───────────
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Alarm Set Alert")
                                    .font(.custom("DM Sans", size: 14))
                                    .foregroundColor(Color.white.opacity(0.85))
                                Text("Alert me when my alarm is set for the next day 3 hours before bedtime")
                                    .font(.custom("DM Sans", size: 12))
                                    .foregroundColor(Color.white.opacity(0.35))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Toggle("", isOn: $wakeReminderEnabled)
                                .labelsHidden()
                                .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .onChange(of: wakeReminderEnabled) { _, enabled in
                            if !enabled { WakeNotification.shared.cancel() }
                        }
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
