import SwiftUI
import UIKit
import Combine
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn

// ── MARK: Settings (root) ─────────────────────────────────────

struct LuniferSettings: View {
    @Binding var answers: SurveyAnswers
    @Environment(\.dismiss) private var dismiss
    @AppStorage("surveyCompleted") private var surveyCompleted = false
    @ObservedObject private var whoopManager = WhoopManager.shared
    @State private var showWhoopDisconnectAlert = false
    @State private var showSignOutAlert = false
    @State private var showSignOutErrorAlert = false
    @State private var showDeleteAlert = false
    @State private var isDeletingAccount = false
    @State private var showDeleteErrorAlert = false
    @State private var deleteErrorMessage = ""
    @State private var signOutErrorMessage = ""

    private var userEmail: String {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
            return "Preview"
        }
        guard FirebaseApp.app() != nil else {
            return "—"
        }
        return Auth.auth().currentUser?.email ?? "—"
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

                            NavigationLink {
                                SleepAndWearablesSettingsView(answers: $answers)
                            } label: {
                                settingsNavRow(title: "Sleep & Wearables")
                            }

                            NavigationLink {
                                AboutSettingsView()
                            } label: {
                                settingsNavRow(title: "About")
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
                                        handleSignOut()
                                    }
                                    Button("No", role: .cancel) { }
                                } message: {
                                    Text("Your latest profile data will remain in Firebase, but this device will clear local account data before returning to sign in.")
                                }
                                // Secondary alert on a separate view so both can fire independently.
                                // SwiftUI only honours the last .alert on a given view; using a
                                // Color.clear background gives this alert its own view node.
                                .background(Color.clear
                                    .alert("Couldn't Sign Out", isPresented: $showSignOutErrorAlert) {
                                        Button("OK", role: .cancel) { }
                                    } message: {
                                        Text(signOutErrorMessage)
                                    }
                                )

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
                                        Task { await performDeletion() }
                                    }
                                    Button("Cancel", role: .cancel) { }
                                } message: {
                                    Text("This will permanently delete your account and all your data. This cannot be undone.")
                                }
                                .background(Color.clear
                                    .alert("Couldn't Delete Account", isPresented: $showDeleteErrorAlert) {
                                        Button("OK", role: .cancel) { }
                                    } message: {
                                        Text(deleteErrorMessage)
                                    }
                                )
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

    // ── MARK: Private helpers ──────────────────────────────────────

    // ── Account deletion ──────────────────────────────────────────
    // Deletes Firestore data first (best-effort), then the Firebase Auth
    // account, then clears local storage.

    private func performDeletion() async {
        guard let user = Auth.auth().currentUser else {
            deleteErrorMessage = "No signed-in user found. Please sign in and try again."
            showDeleteErrorAlert = true
            return
        }
        isDeletingAccount = true

        let db      = Firestore.firestore()
        let userDoc = db.collection("users").document(user.uid)

        // Best-effort Firestore cleanup. If security rules block client-side
        // deletes we log and continue — the Auth account deletion is the
        // critical step. Remaining Firestore data can be purged server-side
        // via a Firebase Auth onDelete Cloud Function once one is wired up.
        do {
            for sub in ["sleepHistory", "alarmInferences", "private"] {
                let snap = try await userDoc.collection(sub).getDocuments()
                for doc in snap.documents {
                    try await doc.reference.delete()
                }
            }
            try await userDoc.delete()
        } catch {
            print("⚠️ Firestore cleanup skipped (rules may restrict client-side delete): \(error.localizedDescription)")
        }

        do {
            try await user.delete()
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

    private func handleSignOut() {
        answers.saveToDefaults()
        answers.saveToFirestore()

        do {
            GIDSignIn.sharedInstance.signOut()
            try Auth.auth().signOut()
            AccountDataManager.shared.clearLocalSessionDataOnSignOut()
            dismiss()
        } catch {
            signOutErrorMessage = (error as NSError).localizedDescription
            showSignOutErrorAlert = true
        }
    }

} // end LuniferSettings

// ── MARK: About You ────────────────────────────────────────────

struct AboutYouSettingsView: View {
    @Binding var answers: SurveyAnswers
    @Environment(\.dismiss) private var dismiss
    @State private var editingField: String? = nil
    // Commute-type gate: shown when user switches to student/commuter from a non-commuter lifestyle
    @State private var showCommuteTypeSheet = false
    @State private var pendingLifestyle: String = ""
    @State private var pendingCommuteMode: String = ""
    // Long-routine warning
    @State private var showLongRoutineAlert = false
    @State private var longRoutineTimeLabel = ""
    // Calendar authorization
    @State private var showCalendarDeniedAlert = false

    private var isCommuterUser: Bool {
        answers.lifestyle == "student" || answers.lifestyle == "commuter"
    }

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

    private var routineLabel: String {
        if answers.routine.auto { return "Auto" }
        let h = answers.routine.hours
        let m = answers.routine.minutes
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    private var commuteModeLabel: String {
        switch answers.commuteMode {
        case "drive":   return "Drive"
        case "transit": return "Transit"
        case "walk":    return "Walk"
        case "bike":    return "Bike"
        default:        return "Not set"
        }
    }

    /// Computes the user's current age from the stored birthday string ("yyyy-MM-dd").
    /// Falls back gracefully for legacy plain-integer age data.
    private var ageDisplayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let birthday = formatter.date(from: answers.age) {
            let years = Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0
            return "\(years)"
        }
        // Legacy: already a plain age number
        return answers.age
    }

    /// Returns a Binding<Date> backed by answers.age for the DatePicker.
    private var birthdayBinding: Binding<Date> {
        Binding(
            get: {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.date(from: answers.age)
                    ?? Calendar.current.date(byAdding: .year, value: -25, to: Date())
                    ?? Date()
            },
            set: { newDate in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                answers.age = formatter.string(from: newDate)
            }
        )
    }

    private var aboutYouDivider: some View {
        Divider()
            .background(Color.white.opacity(0.08))
            .padding(.leading, 16)
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
                        aboutYouRow(label: "Age", value: ageDisplayString, field: "age")
                        aboutYouDivider
                        aboutYouRow(label: "Lifestyle", value: lifestyleLabel, field: "lifestyle")
                        aboutYouDivider
                        aboutYouRow(label: "Calendar", value: calendarLabel, field: "calendar")
                        if answers.lifestyle != "not_working" {
                            aboutYouDivider
                            aboutYouRow(label: "Morning Routine", value: routineLabel, field: "routine")
                        }
                        if isCommuterUser {
                            aboutYouDivider
                            aboutYouRow(label: "Commute Type", value: commuteModeLabel, field: "commuteMode")
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
        .onChange(of: answers.routine) { _, _ in
            answers.saveToDefaults()
            answers.saveToFirestore()
        }
        .onChange(of: answers.commuteMode) { _, _ in
            answers.saveToDefaults()
            answers.saveToFirestore()
        }
        // ── Commute-type gate sheet ───────────────────────────────
        .sheet(isPresented: $showCommuteTypeSheet) {
            CommuteTypeRequiredSheet(selectedMode: $pendingCommuteMode) {
                let wasNotWorking = answers.lifestyle == "not_working"
                answers.lifestyle = pendingLifestyle
                answers.commuteMode = pendingCommuteMode
                // Restore routine default when upgrading from not_working
                if wasNotWorking {
                    answers.routine = TimeValue(hours: 1, minutes: 0, auto: false)
                }
                // onChange handlers on lifestyle/commuteMode/routine will persist the changes
                showCommuteTypeSheet = false
                // Collapse the lifestyle dropdown now that the selection is complete
                editingField = nil
            }
            .interactiveDismissDisabled(true)
            .presentationDetents([.fraction(0.58)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(Color(red: 0.07, green: 0.04, blue: 0.15))
        }
        // ── Long routine warning ──────────────────────────────────
        .alert("Long Morning Routine", isPresented: $showLongRoutineAlert) {
            Button("Yes") {
                // Keep the selected value and close the expanded row
                editingField = nil
            }
            Button("No", role: .cancel) {
                answers.routine = TimeValue(hours: 1, minutes: 0, auto: false)
            }
        } message: {
            Text("\(longRoutineTimeLabel) is a long time for a morning routine. Are you sure that's how long you want Lunifer to remember it for?")
        }
        // ── Calendar access denied ────────────────────────────────
        .alert("Calendar Access Required", isPresented: $showCalendarDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Lunifer needs access to your calendar to set your alarm based on tomorrow's first event. Please tap Open Settings and allow Calendar access.")
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
                        if editingField == field {
                            // Closing the row — check for long routine before collapsing
                            if field == "routine" && !answers.routine.auto && answers.routine.hours > 4 {
                                let h = answers.routine.hours
                                let m = answers.routine.minutes
                                longRoutineTimeLabel = m > 0 ? "\(h) hours \(m) minutes" : "\(h) hours"
                                showLongRoutineAlert = true
                                // Don't collapse yet — alert "Yes" closes it
                            } else {
                                editingField = nil
                            }
                        } else {
                            editingField = field
                        }
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
                        DatePicker(
                            "",
                            selection: birthdayBinding,
                            in: ...Calendar.current.date(byAdding: .year, value: -13, to: Date())!,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .frame(height: 120)
                        .clipped()

                    case "lifestyle":
                        VStack(spacing: 8) {
                            let lifestyleOptions: [(String, String)] = [
                                ("student", "Student"),
                                ("commuter", "Commuter"),
                                ("wfh", "Work From Home"),
                                ("not_working", "Not Working")
                            ]
                            ForEach(lifestyleOptions, id: \.0) { id, title in
                                Button {
                                    let willBeCommuter = id == "student" || id == "commuter"
                                    let isAlreadyCommuter = answers.lifestyle == "student" || answers.lifestyle == "commuter"
                                    if willBeCommuter && !isAlreadyCommuter {
                                        // Gate: require commute type before applying lifestyle change
                                        pendingLifestyle = id
                                        pendingCommuteMode = ""
                                        showCommuteTypeSheet = true
                                    } else {
                                        let wasNotWorking = answers.lifestyle == "not_working"
                                        answers.lifestyle = id
                                        if id == "not_working" {
                                            answers.routine = TimeValue(hours: 0, minutes: 0, auto: false)
                                        } else if wasNotWorking {
                                            answers.routine = TimeValue(hours: 1, minutes: 0, auto: false)
                                        }
                                    }
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
                                    let previousCalendar = answers.calendar
                                    answers.calendar = id
                                    // When switching away from "none", request calendar access
                                    if id != "none" && previousCalendar == "none" {
                                        let status = CalendarManager.shared.authorizationStatus
                                        if status == .denied {
                                            showCalendarDeniedAlert = true
                                        } else if status != .authorized {
                                            Task { await CalendarManager.shared.requestAccess() }
                                        }
                                    }
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

                    case "routine":
                        TimeScalePicker(
                            value: $answers.routine,
                            autoLabel: "Let Lunifer figure this out"
                        )

                    case "commuteMode":
                        VStack(spacing: 8) {
                            ForEach([
                                ("drive",   "car.fill",    "Drive"),
                                ("transit", "tram.fill",   "Transit"),
                                ("walk",    "figure.walk", "Walk"),
                                ("bike",    "bicycle",     "Bike")
                            ], id: \.0) { mode, icon, title in
                                Button {
                                    answers.commuteMode = mode
                                } label: {
                                    HStack {
                                        Image(systemName: icon)
                                            .font(.system(size: 14))
                                            .foregroundColor(answers.commuteMode == mode
                                                ? Color(red: 0.627, green: 0.471, blue: 1.0)
                                                : Color.white.opacity(0.45))
                                            .frame(width: 24)
                                        Text(title)
                                            .font(.custom("DM Sans", size: 14))
                                            .foregroundColor(answers.commuteMode == mode
                                                ? Color.white.opacity(0.95)
                                                : Color.white.opacity(0.7))
                                        Spacer()
                                        if answers.commuteMode == mode {
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
                                                        answers.commuteMode == mode
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

// ── MARK: Sleep & Wearables ────────────────────────────────────

struct SleepAndWearablesSettingsView: View {
    @Binding var answers: SurveyAnswers
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var whoopManager = WhoopManager.shared
    @ObservedObject private var ouraManager  = OuraManager.shared

    @AppStorage(AppPreferencesStore.Keys.hasWearable)               private var hasWearable: Bool      = false
    @AppStorage(AppPreferencesStore.Keys.whoopConnected)            private var whoopConnected: Bool   = false
    @AppStorage(AppPreferencesStore.Keys.whoopRecommendedSleepHours) private var whoopSleepHours: Double = 0
    @AppStorage(AppPreferencesStore.Keys.ouraConnected)             private var ouraConnected: Bool    = false
    @AppStorage(AppPreferencesStore.Keys.ouraRecommendedSleepHours)  private var ouraSleepHours: Double  = 0

    @State private var showSleepSheet = false
    @State private var draftSleep = TimeValue(hours: 8, minutes: 0, auto: false)
    @State private var showWearableWarning = false
    @State private var showDisconnectWhoopAlert = false
    @State private var showDisconnectOuraAlert  = false
    @State private var showOneWearableAlert = false
    @State private var conflictingWearableName = ""

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

    private var sleepSourceLabel: String? {
        if let recommendation = wearableRecommendation {
            return "Set by \(recommendation.provider.displayName)"
        }
        if answers.sleep.auto { return "Learning from your data" }
        return nil
    }

    private var wearableWarningProviderName: String {
        wearableRecommendation?.provider.displayName ?? "wearable"
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.luniferBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ───────────────────────────────
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(Color.white.opacity(0.75))
                            .frame(width: 36, height: 36)
                    }
                    Spacer()
                    Text("Sleep & Wearables")
                        .font(.custom("Cormorant Garamond", size: 28).weight(.light))
                        .foregroundColor(Color.white.opacity(0.9))
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {

                        // ── Sleep Duration ───────────────
                        SettingsSection(title: "Optimal Sleep") {
                            VStack(spacing: 0) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(SleepDurationModel.formatted(recommendedHours))
                                            .font(.libreFranklin(size: 23))
                                            .foregroundColor(Color.white.opacity(0.95))
                                        if let label = sleepSourceLabel {
                                            Text(label)
                                                .font(.custom("DM Sans", size: 12))
                                                .foregroundColor(Color.white.opacity(0.4))
                                        }
                                    }
                                    Spacer()
                                    Button {
                                        draftSleep = answers.sleep
                                        if wearableRecommendation != nil {
                                            showWearableWarning = true
                                        } else {
                                            showSleepSheet = true
                                        }
                                    } label: {
                                        Text("Change")
                                            .font(.custom("DM Sans", size: 13))
                                            .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
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

                        // ── Wearables ────────────────────
                        SettingsSection(title: "Wearables") {
                            VStack(spacing: 12) {
                                wearableRow(
                                    name: "WHOOP",
                                    imageName: "WhoopWordmark",
                                    isConnected: whoopConnected,
                                    isLoading: whoopManager.isLoading,
                                    imageHeight: 26,
                                    onConnect: {
                                        if ouraConnected {
                                            conflictingWearableName = "Oura Ring"
                                            showOneWearableAlert = true
                                        } else {
                                            Task {
                                                try? await WhoopManager.shared.connect()
                                            }
                                        }
                                    },
                                    onDisconnect: {
                                        showDisconnectWhoopAlert = true
                                    }
                                )

                                wearableRow(
                                    name: "Oura Ring",
                                    imageName: "OuraWordmark",
                                    isConnected: ouraConnected,
                                    isLoading: ouraManager.isLoading,
                                    imageHeight: 22,
                                    onConnect: {
                                        if whoopConnected {
                                            conflictingWearableName = "WHOOP"
                                            showOneWearableAlert = true
                                        } else {
                                            Task {
                                                try? await OuraManager.shared.connect()
                                            }
                                        }
                                    },
                                    onDisconnect: {
                                        showDisconnectOuraAlert = true
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // ── Alerts ───────────────────────────────────────────
        .alert("Override wearable recommendation?", isPresented: $showWearableWarning) {
            Button("Set Manually", role: .destructive) {
                showSleepSheet = true
            }
            Button("Keep Recommendation", role: .cancel) { }
        } message: {
            Text("Your sleep goal is set by your \(wearableWarningProviderName). Setting it manually will replace that recommendation.")
        }
        .alert("Disconnect WHOOP?", isPresented: $showDisconnectWhoopAlert) {
            Button("Disconnect", role: .destructive) {
                WhoopManager.shared.disconnect()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your sleep recommendation will revert to your manual setting or Lunifer's age-based estimate.")
        }
        .alert("Disconnect Oura Ring?", isPresented: $showDisconnectOuraAlert) {
            Button("Disconnect", role: .destructive) {
                OuraManager.shared.disconnect()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your sleep recommendation will revert to your manual setting or Lunifer's age-based estimate.")
        }
        .alert("Only One Wearable at a Time", isPresented: $showOneWearableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You're already connected to \(conflictingWearableName). Disconnect it first before connecting a different wearable.")
        }
        // ── Sleep edit sheet (same as old SleepInsights sheet) ──
        .sheet(isPresented: $showSleepSheet) {
            SleepEditSheet(sleep: $draftSleep) {
                answers.sleep = draftSleep
                answers.saveToDefaults()
                answers.saveToFirestore()
                showSleepSheet = false
            }
            .presentationDetents([.fraction(0.52)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(red: 0.07, green: 0.04, blue: 0.15))
        }
    }

    // ── Wearable row builder ─────────────────────────────────

    @ViewBuilder
    private func wearableRow(
        name: String,
        imageName: String,
        isConnected: Bool,
        isLoading: Bool,
        imageHeight: CGFloat = 16,
        onConnect: @escaping () -> Void,
        onDisconnect: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(imageName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: imageHeight)

            Spacer()

            if isLoading {
                ProgressView()
                    .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
                    .scaleEffect(0.8)
            } else if isConnected {
                Button(action: onDisconnect) {
                    Text("Disconnect")
                        .font(.custom("DM Sans", size: 13))
                        .foregroundColor(Color.red.opacity(0.7))
                }
            } else {
                Button(action: onConnect) {
                    Text("Connect")
                        .font(.custom("DM Sans", size: 13))
                        .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.12))
                                .overlay(
                                    Capsule()
                                        .stroke(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.3), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
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
}

// ── MARK: Wake Days ───────────────────────────────────────────

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
                .padding(.bottom, 12)

                Text("Choose the days you need Lunifer to wake you up.")
                    .font(.custom("DM Sans", size: 14))
                    .foregroundColor(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

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
    @AppStorage("allNotificationsEnabled")  private var allNotificationsEnabled: Bool  = true
    @AppStorage("batteryAlertEnabled")      private var batteryAlertEnabled: Bool      = true
    @AppStorage("wakeReminderEnabled")      private var wakeReminderEnabled: Bool      = true
    @AppStorage("commuteReminderEnabled")   private var commuteReminderEnabled: Bool   = true
    @AppStorage("restDayReminderEnabled")   private var restDayReminderEnabled: Bool   = true

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
                    VStack(spacing: 12) {

                        // ── Master toggle ─────────────────
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("All Notifications")
                                    .font(.custom("DM Sans", size: 14))
                                    .foregroundColor(Color.white.opacity(0.85))
                                Text("Turn all Lunifer notifications on or off at once")
                                    .font(.custom("DM Sans", size: 12))
                                    .foregroundColor(Color.white.opacity(0.35))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Toggle("", isOn: $allNotificationsEnabled)
                                .labelsHidden()
                                .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
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
                        .onChange(of: allNotificationsEnabled) { _, enabled in
                            if !enabled {
                                // Cancel every active notification in the backend
                                batteryAlertEnabled    = false
                                wakeReminderEnabled    = false
                                commuteReminderEnabled = false
                                restDayReminderEnabled = false
                                WakeNotification.shared.cancel()
                                CommuteNotification.shared.cancelAll()
                                BatteryAlarmNotification.shared.cancelWarning()
                                RestDayEventNotification.shared.cancel()
                            } else {
                                // Re-enable all individual toggles
                                batteryAlertEnabled    = true
                                wakeReminderEnabled    = true
                                commuteReminderEnabled = true
                                restDayReminderEnabled = true
                            }
                        }

                        // ── Individual toggles ────────────
                        VStack(spacing: 0) {
                            // ── Battery alert row ─────────────
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Battery Alert")
                                        .font(.custom("DM Sans", size: 14))
                                        .foregroundColor(Color.white.opacity(allNotificationsEnabled ? 0.85 : 0.35))
                                    Text("Warn me if my phone won't survive until my alarm")
                                        .font(.custom("DM Sans", size: 12))
                                        .foregroundColor(Color.white.opacity(allNotificationsEnabled ? 0.35 : 0.18))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Toggle("", isOn: $batteryAlertEnabled)
                                    .labelsHidden()
                                    .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
                                    .disabled(!allNotificationsEnabled)
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
                                        .foregroundColor(Color.white.opacity(allNotificationsEnabled ? 0.85 : 0.35))
                                    Text("Alert me when my alarm is set for the next day 3 hours before bedtime")
                                        .font(.custom("DM Sans", size: 12))
                                        .foregroundColor(Color.white.opacity(allNotificationsEnabled ? 0.35 : 0.18))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Toggle("", isOn: $wakeReminderEnabled)
                                    .labelsHidden()
                                    .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
                                    .disabled(!allNotificationsEnabled)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .onChange(of: wakeReminderEnabled) { _, enabled in
                                if !enabled { WakeNotification.shared.cancel() }
                            }

                            Divider()
                                .background(Color.white.opacity(0.08))
                                .padding(.leading, 16)

                            // ── Commute reminder row ──────────
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Commute Reminder")
                                        .font(.custom("DM Sans", size: 14))
                                        .foregroundColor(Color.white.opacity(allNotificationsEnabled ? 0.85 : 0.35))
                                    Text("Notify me 15 minutes before I need to leave for work")
                                        .font(.custom("DM Sans", size: 12))
                                        .foregroundColor(Color.white.opacity(allNotificationsEnabled ? 0.35 : 0.18))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Toggle("", isOn: $commuteReminderEnabled)
                                    .labelsHidden()
                                    .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
                                    .disabled(!allNotificationsEnabled)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .onChange(of: commuteReminderEnabled) { _, enabled in
                                if !enabled { CommuteNotification.shared.cancelAll() }
                            }

                            Divider()
                                .background(Color.white.opacity(0.08))
                                .padding(.leading, 16)

                            // ── Rest day reminder row ──────────
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Rest Day Reminder")
                                        .font(.custom("DM Sans", size: 14))
                                        .foregroundColor(Color.white.opacity(allNotificationsEnabled ? 0.85 : 0.35))
                                    Text("Notify me on rest days if I have an early event the next morning")
                                        .font(.custom("DM Sans", size: 12))
                                        .foregroundColor(Color.white.opacity(allNotificationsEnabled ? 0.35 : 0.18))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Toggle("", isOn: $restDayReminderEnabled)
                                    .labelsHidden()
                                    .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
                                    .disabled(!allNotificationsEnabled)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .onChange(of: restDayReminderEnabled) { _, enabled in
                                if !enabled { RestDayEventNotification.shared.cancel() }
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
                        .opacity(allNotificationsEnabled ? 1 : 0.6)
                    }
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

// ── MARK: Commute Type Required Sheet ─────────────────────────
// Presented (non-dismissable) when the user switches to a commuter
// lifestyle in Settings without a commute mode already selected.

struct CommuteTypeRequiredSheet: View {
    @Binding var selectedMode: String
    let onConfirm: () -> Void

    private let modes: [(id: String, icon: String, label: String)] = [
        ("drive",   "car.fill",    "Drive"),
        ("transit", "tram.fill",   "Transit"),
        ("walk",    "figure.walk", "Walk"),
        ("bike",    "bicycle",     "Bike")
    ]

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.04, blue: 0.15).ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header ────────────────────────────────────────
                Text("How do you commute?")
                    .font(.custom("Cormorant Garamond", size: 26).weight(.light))
                    .foregroundColor(Color.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .padding(.top, 36)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                Text("Lunifer will calculate your commute time automatically.")
                    .font(.custom("DM Sans", size: 13))
                    .foregroundColor(Color.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 32)

                // ── Transport mode grid ───────────────────────────
                HStack(spacing: 10) {
                    ForEach(modes, id: \.id) { mode in
                        let selected = selectedMode == mode.id
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedMode = mode.id
                            }
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 20, weight: .regular))
                                    .foregroundColor(selected
                                        ? Color.white.opacity(0.95)
                                        : Color.white.opacity(0.3))
                                Text(mode.label)
                                    .font(.custom("DM Sans", size: 12))
                                    .foregroundColor(selected
                                        ? Color.white.opacity(0.85)
                                        : Color.white.opacity(0.3))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 68)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selected
                                        ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.18)
                                        : Color.white.opacity(0.03))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selected
                                                ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.65)
                                                : Color.white.opacity(0.06),
                                                lineWidth: 1.5)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: selected)
                    }
                }
                .padding(.horizontal, 24)

                // ── Hint text ─────────────────────────────────────
                if selectedMode.isEmpty {
                    Text("Select a commute type above to continue.")
                        .font(.custom("DM Sans", size: 13))
                        .foregroundColor(Color.white.opacity(0.35))
                        .padding(.top, 14)
                        .transition(.opacity)
                }

                Spacer()

                // ── Confirm button ────────────────────────────────
                Button(action: onConfirm) {
                    Text("Confirm →")
                        .font(.custom("DM Sans", size: 15).weight(.medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(LinearGradient(
                                    colors: [
                                        Color(red: 0.471, green: 0.314, blue: 0.863).opacity(0.9),
                                        Color(red: 0.314, green: 0.196, blue: 0.706).opacity(0.9)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .opacity(selectedMode.isEmpty ? 0.35 : 1.0)
                        )
                }
                .disabled(selectedMode.isEmpty)
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
        }
    }
}

// ── MARK: About ────────────────────────────────────────────────

struct AboutSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL)  private var openURL

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
                    Text("About")
                        .font(.custom("Cormorant Garamond", size: 28).weight(.light))
                        .foregroundColor(Color.white.opacity(0.9))
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                // ── Links ─────────────────────────────────
                VStack(spacing: 0) {
                    Button {
                        openURL(URL(string: "https://lunifer-ce086.web.app/privacy-policy.html")!)
                    } label: {
                        HStack {
                            Text("Privacy Policy")
                                .font(.custom("DM Sans", size: 15))
                                .foregroundColor(Color.white.opacity(0.85))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .light))
                                .foregroundColor(Color.white.opacity(0.25))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.leading, 16)

                    Button {
                        openURL(URL(string: "https://lunifer-ce086.web.app/terms.html")!)
                    } label: {
                        HStack {
                            Text("Terms & Conditions")
                                .font(.custom("DM Sans", size: 15))
                                .foregroundColor(Color.white.opacity(0.85))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .light))
                                .foregroundColor(Color.white.opacity(0.25))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
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
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
