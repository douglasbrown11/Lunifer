import SwiftUI
import UIKit
import MapKit
import CoreLocation
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
    @State private var showPasswordPrompt = false
    @State private var reauthPassword = ""

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
                                        Task { await startDeletion() }
                                    }
                                    Button("Cancel", role: .cancel) { }
                                } message: {
                                    Text("This will permanently delete your account and all your data. This cannot be undone.")
                                }
                                // Each secondary alert lives on its own Color.clear background view
                                // so SwiftUI can present them independently. Chaining multiple
                                // .alert modifiers on the same view causes all but the last to
                                // be silently ignored.
                                .background(Color.clear
                                    .alert("Enter your password to confirm", isPresented: $showPasswordPrompt) {
                                        SecureField("Password", text: $reauthPassword)
                                        Button("Delete Account", role: .destructive) {
                                            Task { await reauthenticateAndDelete(password: reauthPassword) }
                                        }
                                        Button("Cancel", role: .cancel) { reauthPassword = ""; isDeletingAccount = false }
                                    } message: {
                                        Text("For security, please re-enter your password to delete your account.")
                                    }
                                )
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
        } else if providers.contains("microsoft.com") {
            // Microsoft users: reauthenticate via OAuth prompt
            await reauthenticateWithMicrosoft()
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

    /// Reauthenticates a Microsoft (Outlook) user via OAuth, then deletes.
    private func reauthenticateWithMicrosoft() async {
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

            let provider = OAuthProvider(providerID: "microsoft.com")
            provider.scopes = ["email", "profile", "openid"]
            provider.customParameters = ["prompt": "select_account"]

            let credential = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthCredential, Error>) in
                provider.getCredentialWith(presentingVC as? AuthUIDelegate) { credential, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let credential {
                        continuation.resume(returning: credential)
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "LuniferSettings",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "No credential returned."]
                        ))
                    }
                }
            }

            guard let user = Auth.auth().currentUser else {
                isDeletingAccount = false
                return
            }
            try await user.reauthenticate(with: credential)
            await performDeletion(user: user)
        } catch {
            isDeletingAccount = false
            let nsError = error as NSError
            // ASWebAuthenticationSession cancellation — user tapped Cancel
            if nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession" && nsError.code == 1 {
                return
            }
            deleteErrorMessage = nsError.localizedDescription
            showDeleteErrorAlert = true
            print("❌ Microsoft reauthentication failed: \(nsError.localizedDescription)")
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
            for sub in ["sleepHistory", "alarmInferences", "private"] {
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

    // ── Home location persistence ─────────────────────────────
    @AppStorage("homeLocationSet")  private var homeLocationSet: Bool = false
    @AppStorage("homeLocationName") private var homeLocationName: String = ""
    @State private var showHomeSheet = false

    private var homeLocationDisplayName: String {
        if homeLocationSet && !homeLocationName.isEmpty { return homeLocationName }
        if homeLocationSet { return "Location set" }
        return "Learning your location..."
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
                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.leading, 16)
                        homeLocationRow()
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
        .sheet(isPresented: $showHomeSheet) {
            HomeLocationSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color(red: 0.06, green: 0.03, blue: 0.14))
        }
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
    private func homeLocationRow() -> some View {
        HStack {
            Text("Home")
                .font(.custom("DM Sans", size: 14))
                .foregroundColor(Color.white.opacity(0.45))

            Text(homeLocationDisplayName)
                .font(.custom("DM Sans", size: 14))
                .foregroundColor(homeLocationSet ? Color.white.opacity(0.85) : Color.white.opacity(0.35))
                .padding(.leading, 12)

            Spacer()

            Button {
                showHomeSheet = true
            } label: {
                Text(homeLocationSet ? "Change" : "Set")
                    .font(.custom("DM Sans", size: 13))
                    .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0))
            }
            .padding(.leading, 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
                            let lifestyleOptions: [(String, String)] = [
                                ("student", "Student"),
                                ("commuter", "Commuter"),
                                ("wfh", "Work From Home"),
                                ("not_working", "Not Working")
                            ]
                            ForEach(lifestyleOptions, id: \.0) { id, title in
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

// ── MARK: Home Location Search Completer ───────────────────────

final class HomeLocationSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    @Published var searchText: String = "" {
        didSet { completer.queryFragment = searchText }
    }

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}

// ── MARK: Home Location Sheet ──────────────────────────────────

struct HomeLocationSheet: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("homeLatitude")    private var homeLatitude: Double = 0
    @AppStorage("homeLongitude")   private var homeLongitude: Double = 0
    @AppStorage("homeLocationSet") private var homeLocationSet: Bool = false
    @AppStorage("homeLocationName") private var homeLocationName: String = ""

    @StateObject private var completer = HomeLocationSearchCompleter()
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var selectedCoordinate: CLLocationCoordinate2D? = nil
    @State private var selectedAddress: String = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.03, blue: 0.14).ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Handle ────────────────────────────────
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)
                    .padding(.bottom, 14)

                // ── Title ─────────────────────────────────
                Text("Set Home Location")
                    .font(.custom("Cormorant Garamond", size: 26).weight(.light))
                    .foregroundColor(Color.white.opacity(0.9))
                    .padding(.bottom, 14)

                Rectangle()
                    .fill(Color.white.opacity(0.95))
                    .frame(height: 1)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 14)

                // ── Search bar ────────────────────────────
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(Color.white.opacity(0.35))
                    TextField("Search address...", text: $completer.searchText)
                        .font(.custom("DM Sans", size: 14))
                        .foregroundColor(Color.white.opacity(0.85))
                        .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
                        .focused($searchFocused)
                        .submitLabel(.search)
                    if !completer.searchText.isEmpty {
                        Button {
                            completer.searchText = ""
                            selectedCoordinate = nil
                            selectedAddress = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color.white.opacity(0.3))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                // ── Suggestions ───────────────────────────
                if !completer.results.isEmpty && !completer.searchText.isEmpty {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(Array(completer.results.prefix(4).enumerated()), id: \.offset) { index, result in
                                Button {
                                    selectSuggestion(result)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "mappin")
                                            .font(.system(size: 11, weight: .light))
                                            .foregroundColor(Color.white.opacity(0.25))
                                            .frame(width: 16)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(result.title)
                                                .font(.custom("DM Sans", size: 13))
                                                .foregroundColor(Color.white.opacity(0.85))
                                                .lineLimit(1)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            if !result.subtitle.isEmpty {
                                                Text(result.subtitle)
                                                    .font(.custom("DM Sans", size: 11))
                                                    .foregroundColor(Color.white.opacity(0.35))
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                                if index < min(completer.results.count, 4) - 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.05))
                                        .padding(.leading, 40)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.04))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        )
                        .padding(.horizontal, 16)
                    }
                    .frame(maxHeight: 180)
                    .padding(.bottom, 8)
                }

                // ── Map ───────────────────────────────────
                ZStack(alignment: .bottom) {
                    Map(position: $mapPosition) {
                        if let coord = selectedCoordinate {
                            Marker("Home", coordinate: coord)
                                .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
                        }
                    }
                    .colorScheme(.dark)
                    .ignoresSafeArea(edges: .bottom)

                    if selectedCoordinate != nil {
                        VStack(spacing: 0) {
                            LinearGradient(
                                colors: [
                                    Color(red: 0.06, green: 0.03, blue: 0.14).opacity(0),
                                    Color(red: 0.06, green: 0.03, blue: 0.14).opacity(0.96)
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: 56)

                            VStack(spacing: 8) {
                                if !selectedAddress.isEmpty {
                                    Text(selectedAddress)
                                        .font(.custom("DM Sans", size: 12))
                                        .foregroundColor(Color.white.opacity(0.55))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                }
                                Button {
                                    confirmLocation()
                                } label: {
                                    Text("Confirm Home")
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
                                        )
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 36)
                            }
                            .background(Color(red: 0.06, green: 0.03, blue: 0.14).opacity(0.96))
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
        .onAppear {
            if homeLocationSet {
                let coord = CLLocationCoordinate2D(latitude: homeLatitude, longitude: homeLongitude)
                selectedCoordinate = coord
                selectedAddress = homeLocationName
                completer.searchText = homeLocationName
                mapPosition = .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            } else {
                mapPosition = .userLocation(fallback: .automatic)
            }
        }
    }

    private func selectSuggestion(_ result: MKLocalSearchCompletion) {
        searchFocused = false
        let request = MKLocalSearch.Request(completion: result)
        MKLocalSearch(request: request).start { response, _ in
            guard let item = response?.mapItems.first else { return }
            let coord = item.location.coordinate
            selectedCoordinate = coord
            selectedAddress = [result.title, result.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
            withAnimation {
                mapPosition = .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
        }
    }

    private func confirmLocation() {
        guard let coord = selectedCoordinate else { return }
        homeLatitude = coord.latitude
        homeLongitude = coord.longitude
        homeLocationSet = true
        homeLocationName = selectedAddress
        dismiss()
    }
}

// ── MARK: Wake Days ────────────────────────────────────────────

// ── MARK: Sleep & Wearables ────────────────────────────────────

struct SleepAndWearablesSettingsView: View {
    @Binding var answers: SurveyAnswers
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var whoopManager = WhoopManager.shared
    @ObservedObject private var ouraManager  = OuraManager.shared

    @AppStorage("whoopConnected")             private var whoopConnected: Bool   = false
    @AppStorage("whoopRecommendedSleepHours") private var whoopSleepHours: Double = 0
    @AppStorage("ouraConnected")              private var ouraConnected: Bool    = false
    @AppStorage("ouraRecommendedSleepHours")  private var ouraSleepHours: Double  = 0

    @State private var showSleepSheet = false
    @State private var draftSleep = TimeValue(hours: 8, minutes: 0, auto: false)
    @State private var showWearableWarning = false
    @State private var showDisconnectWhoopAlert = false
    @State private var showDisconnectOuraAlert  = false

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

    private var sleepSourceLabel: String {
        if isWhoopDriven { return "Set by WHOOP" }
        if isOuraDriven  { return "Set by Oura Ring" }
        if answers.sleep.auto { return "Learning from your data" }
        return "Set manually"
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
                                            .font(.custom("Libre Franklin", size: 28).weight(.light))
                                            .foregroundColor(Color.white.opacity(0.95))
                                        Text(sleepSourceLabel)
                                            .font(.custom("DM Sans", size: 12))
                                            .foregroundColor(Color.white.opacity(0.4))
                                    }
                                    Spacer()
                                    Button {
                                        draftSleep = answers.sleep
                                        if isWhoopDriven || isOuraDriven {
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
                                    onConnect: {
                                        Task {
                                            try? await WhoopManager.shared.connect()
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
                                    onConnect: {
                                        Task {
                                            try? await OuraManager.shared.connect()
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
            Text("Your sleep goal is set by your \(isWhoopDriven ? "WHOOP" : "Oura Ring"). Setting it manually will replace that recommendation.")
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
        onConnect: @escaping () -> Void,
        onDisconnect: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(imageName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 16)

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
    @AppStorage("batteryAlertEnabled")    private var batteryAlertEnabled: Bool    = true
    @AppStorage("wakeReminderEnabled")    private var wakeReminderEnabled: Bool    = true
    @AppStorage("commuteReminderEnabled") private var commuteReminderEnabled: Bool = true

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

                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.leading, 16)

                        // ── Commute reminder row ──────────
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Commute Reminder")
                                    .font(.custom("DM Sans", size: 14))
                                    .foregroundColor(Color.white.opacity(0.85))
                                Text("Notify me 15 minutes before I need to leave for work")
                                    .font(.custom("DM Sans", size: 12))
                                    .foregroundColor(Color.white.opacity(0.35))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Toggle("", isOn: $commuteReminderEnabled)
                                .labelsHidden()
                                .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .onChange(of: commuteReminderEnabled) { _, enabled in
                            if !enabled { CommuteNotification.shared.cancelAll() }
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
