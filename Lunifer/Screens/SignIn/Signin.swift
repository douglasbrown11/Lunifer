import SwiftUI
import UIKit
import FirebaseAuth
import GoogleSignIn
import AuthenticationServices
import CryptoKit

// ── MARK: Types ──────────────────────────────────────────────

private enum SigninMode {
    case signIn, create
}

// ── MARK: Error mapping ──────────────────────────────────────
// Mirrors the getFriendlyError() function in luniferAuth.jsx

private func friendlySigninError(_ error: Error) -> String {
    let nsError = error as NSError

    // Google Sign In cancellation (kGIDSignInErrorDomain, code -5)
    if nsError.domain.contains("GIDSignIn") && nsError.code == -5 {
        return "Sign in was cancelled."
    }

    // Microsoft / ASWebAuthenticationSession cancellation
    if nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession" && nsError.code == 1 {
        return "Sign in was cancelled."
    }

    // Sign in with Apple cancellation
    if let asError = error as? ASAuthorizationError, asError.code == .canceled {
        return "Sign in was cancelled."
    }

    switch nsError.code {
    case AuthErrorCode.emailAlreadyInUse.rawValue:
        return "An account with this email already exists."
    case AuthErrorCode.invalidEmail.rawValue:
        return "Please enter a valid email address."
    case AuthErrorCode.weakPassword.rawValue:
        return "Password must be at least 6 characters."
    case AuthErrorCode.userNotFound.rawValue:
        return "No account found with this email."
    case AuthErrorCode.wrongPassword.rawValue:
        return "Incorrect password. Please try again."
    case AuthErrorCode.tooManyRequests.rawValue:
        return "Too many attempts. Please try again later."
    default:
        return "Something went wrong. Please try again."
    }
}

// ── MARK: Input field ────────────────────────────────────────

private struct LuniferInputField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .focused($focused)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .focused($focused)
            }
        }
        .font(.custom("DM Sans", size: 15))
        .foregroundColor(Color.white.opacity(0.9))
        .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(focused
                      ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.06)
                      : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(focused
                                ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.6)
                                : Color.white.opacity(0.08),
                                lineWidth: 1.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .animation(.easeInOut(duration: 0.2), value: focused)
    }
}

// ── MARK: LuniferSignin ───────────────────────────────────────

struct LuniferSignin: View {
    var onSignedIn: (_ isNewUser: Bool) async -> Void = { _ in }

    @State private var mode: SigninMode = .create
    @State private var email = ""
    @State private var password = ""
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var agreedToTerms: Bool = false

    /// Holds the raw (un-hashed) nonce while a Sign in with Apple flow is
    /// in progress. Firebase requires the original nonce when exchanging
    /// the Apple identity token for an `OAuthCredential`.
    @State private var currentAppleNonce: String? = nil

    private var canSubmit: Bool { !email.isEmpty && password.count >= 6 }

    private var termsAttributedString: AttributedString {
        let tosURL  = URL(string: "https://lunifer-ce086.web.app/terms.html")!
        let ppURL   = URL(string: "https://lunifer-ce086.web.app/privacy-policy.html")!
        let base    = Font.custom("DM Sans", size: 12)
        let muted   = Color.white.opacity(0.35)
        let accent  = Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.85)
        var s   = AttributedString("By continuing, you agree to our "); s.font = base;   s.foregroundColor = muted
        var tos = AttributedString("Terms of Service");                  tos.font = base; tos.foregroundColor = accent; tos.link = tosURL
        var and = AttributedString(" and ");                             and.font = base; and.foregroundColor = muted
        var pp  = AttributedString("Privacy Policy");                   pp.font = base;  pp.foregroundColor = accent;  pp.link = ppURL
        var dot = AttributedString(".");                                 dot.font = base; dot.foregroundColor = muted
        return s + tos + and + pp + dot
    }

    var body: some View {
        ZStack {
            LuniferBackground(showStars: false)

            ScrollView {
                VStack(spacing: 0) {

                    FloatingMoon()
                        .padding(.bottom, 10)

                    Text("Lunifer")
                        .font(.custom("Cormorant Garamond", size: 30))
                        .fontWeight(.light)
                        .foregroundColor(Color.white.opacity(0.95))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 14)


                    // ── Error box ────────────────────────────
                    if let error = errorMessage {
                        Text(error)
                            .font(.custom("DM Sans", size: 13))
                            .foregroundColor(Color(red: 1, green: 0.392, blue: 0.392).opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 1, green: 0.314, blue: 0.314).opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 1, green: 0.314, blue: 0.314).opacity(0.15), lineWidth: 1)
                                    )
                            )
                            .padding(.bottom, 14)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }

                    // ── Inputs ───────────────────────────────
                    VStack(spacing: 12) {
                        LuniferInputField(placeholder: "Email address", text: $email)
                        LuniferInputField(placeholder: "Password", text: $password, isSecure: true)
                    }
                    .padding(.bottom, 16)

                    // ── Primary button ───────────────────────
                    Button { handleEmailSignin() } label: {
                        ZStack {
                            if loading {
                                ProgressView().tint(.white)
                            } else {
                                Text(mode == .signIn ? "Sign In" : "Create Account")
                                    .font(.custom("DM Sans", size: 15).weight(.medium))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(LinearGradient(
                                    colors: [
                                        Color(red: 0.471, green: 0.314, blue: 0.863),
                                        Color(red: 0.314, green: 0.196, blue: 0.706),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.6), lineWidth: 1.5)
                                )
                        )
                        .opacity(canSubmit && !loading ? 1.0 : 0.4)
                    }
                    .disabled(!canSubmit || loading)
                    .padding(.bottom, 20)

                    // ── Divider ──────────────────────────────
                    HStack(spacing: 12) {
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                        Text("or")
                            .font(.custom("DM Sans", size: 12))
                            .foregroundColor(Color.white.opacity(0.25))
                            .kerning(0.5)
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    }
                    .padding(.bottom, 20)

                    // ── Apple button ─────────────────────────
                    // Required by App Store Review Guideline 4.8 whenever
                    // any third-party login is offered. Visual style matches
                    // the Google and Outlook buttons below.
                    Button { handleAppleSignIn() } label: {
                        HStack(spacing: 10) {
                            AppleLogoView()
                            Text("Continue with Apple")
                                .font(.custom("DM Sans", size: 15))
                                .foregroundColor(Color.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                    .disabled(loading)
                    .padding(.bottom, 12)

                    // ── Google button ────────────────────────
                    Button { handleGoogleSignIn() } label: {
                        HStack(spacing: 10) {
                            GoogleLogoView()
                            Text("Continue with Google")
                                .font(.custom("DM Sans", size: 15))
                                .foregroundColor(Color.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                    .disabled(loading)
                    .padding(.bottom, 12)

                    // ── Outlook button ───────────────────────
                    Button { handleMicrosoftSignIn() } label: {
                        HStack(spacing: 10) {
                            MicrosoftLogoView()
                            Text("Continue with Outlook")
                                .font(.custom("DM Sans", size: 15))
                                .foregroundColor(Color.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                    .disabled(loading)
                    .padding(.bottom, 24)

                    // ── Toggle mode ──────────────────────────
                    HStack(spacing: 4) {
                        Text(mode == .signIn
                             ? "Don't have an account?"
                             : "Already have an account?")
                            .font(.custom("DM Sans", size: 14))
                            .foregroundColor(Color.white.opacity(0.3))

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                mode = mode == .signIn ? .create : .signIn
                                errorMessage = nil
                            }
                        } label: {
                            Text(mode == .signIn ? "Create one" : "Sign in")
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.9))
                        }
                    }
                }
                .padding(.horizontal, 62)
                .padding(.top, 115)
                .padding(.bottom, 110)   // leave room for the pinned checkbox panel
                .frame(maxWidth: .infinity)
            }

            // ── Pinned terms checkbox card ────────────────────
            VStack {
                Spacer()
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { agreedToTerms.toggle() }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(agreedToTerms
                                      ? Color(red: 0.627, green: 0.471, blue: 1.0)
                                      : Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(agreedToTerms
                                                ? Color.clear
                                                : Color.white.opacity(0.18),
                                                lineWidth: 1.5)
                                )
                                .frame(width: 18, height: 18)
                            if agreedToTerms {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.top, 1)
                    .padding(.horizontal, 5)

                    Text(termsAttributedString)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.12, green: 0.08, blue: 0.20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 29)
                .padding(.bottom, 52)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }

    // ── MARK: Actions ────────────────────────────────────────

    private func handleEmailSignin() {
        guard canSubmit else { return }
        guard agreedToTerms else {
            withAnimation { errorMessage = "Please agree to the Terms of Service and Privacy Policy to continue." }
            return
        }
        Task { @MainActor in
            loading = true
            errorMessage = nil
            do {
                if mode == .create {
                    _ = try await Auth.auth().createUser(withEmail: email, password: password)
                    await onSignedIn(true)
                } else {
                    _ = try await Auth.auth().signIn(withEmail: email, password: password)
                    await onSignedIn(false)
                }
            } catch {
                errorMessage = friendlySigninError(error)
            }
            loading = false
        }
    }

    // ── MARK: Apple sign-in ──────────────────────────────────
    // SETUP REQUIRED before this works:
    //   1. Xcode → Lunifer target → Signing & Capabilities → + Capability → "Sign in with Apple".
    //      (The Lunifer.entitlements file already contains the
    //      `com.apple.developer.applesignin` key.)
    //   2. Apple Developer Portal → Identifiers → select the Lunifer App ID →
    //      enable "Sign In with Apple", then re-download the provisioning profile.
    //   3. Firebase Console → Authentication → Sign-in method → enable Apple.
    //      No client ID is needed for native iOS Apple Sign-In through Firebase.
    //
    // FLOW:
    //   • Generate a random nonce and SHA-256-hash it.
    //   • Pass the hashed nonce to ASAuthorizationAppleIDRequest so Apple
    //     binds the resulting identity token to it.
    //   • After Apple returns the identity token, exchange the *raw* nonce
    //     plus identity token for a Firebase OAuthCredential.

    private func handleAppleSignIn() {
        guard agreedToTerms else {
            withAnimation { errorMessage = "Please agree to the Terms of Service and Privacy Policy to continue." }
            return
        }

        Task { @MainActor in
            loading = true
            errorMessage = nil

            // Generate and remember the raw nonce. The hashed version is
            // what we send to Apple; the raw version is what Firebase needs.
            let rawNonce = AppleSignInNonce.makeRandomNonce()
            currentAppleNonce = rawNonce

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleSignInNonce.sha256(rawNonce)

            let coordinator = AppleSignInCoordinator()
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = coordinator
            controller.presentationContextProvider = coordinator

            do {
                let credential = try await coordinator.perform(controller: controller)

                guard let identityTokenData = credential.identityToken,
                      let identityTokenString = String(data: identityTokenData, encoding: .utf8) else {
                    errorMessage = "Something went wrong. Please try again."
                    currentAppleNonce = nil
                    loading = false
                    return
                }

                // Build a full-name string only when Apple actually returned
                // name components (only on first sign-up). This becomes the
                // Firebase Auth `displayName` for new users.
                let fullName: String? = {
                    guard let components = credential.fullName else { return nil }
                    let formatter = PersonNameComponentsFormatter()
                    let formatted = formatter.string(from: components)
                    return formatted.isEmpty ? nil : formatted
                }()

                let firebaseCredential = OAuthProvider.appleCredential(
                    withIDToken: identityTokenString,
                    rawNonce: rawNonce,
                    fullName: credential.fullName
                )

                let authResult = try await Auth.auth().signIn(with: firebaseCredential)

                // First-sign-in only: Apple returns the user's name once.
                // Persist it to the Firebase Auth profile so the rest of
                // the app can read `Auth.auth().currentUser?.displayName`.
                if let fullName,
                   authResult.additionalUserInfo?.isNewUser == true,
                   (authResult.user.displayName ?? "").isEmpty {
                    let change = authResult.user.createProfileChangeRequest()
                    change.displayName = fullName
                    try? await change.commitChanges()
                }

                currentAppleNonce = nil
                await onSignedIn(authResult.additionalUserInfo?.isNewUser ?? false)
            } catch {
                currentAppleNonce = nil
                errorMessage = friendlySigninError(error)
            }
            loading = false
        }
    }

    // ── MARK: Microsoft sign-in ──────────────────────────────
    // SETUP REQUIRED before this works:
    //   1. Firebase Console → Authentication → Sign-in method → Add provider → Microsoft
    //      Paste in your Azure Application (client) ID and set the redirect URI.
    //   2. Azure Portal → App registrations → New registration
    //      • Supported account types: "Accounts in any org + personal Microsoft accounts"
    //      • Redirect URI: the custom scheme Firebase gives you (e.g. msauth.<bundle-id>://auth)
    //      • Add API permission: Calendars.Read (Microsoft Graph, Delegated)
    //   3. In Azure, copy the Application (client) ID into Firebase Console.

    private func handleMicrosoftSignIn() {
        guard agreedToTerms else {
            withAnimation { errorMessage = "Please agree to the Terms of Service and Privacy Policy to continue." }
            return
        }
        Task { @MainActor in
            loading = true
            errorMessage = nil

            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                  let window = windowScene.windows.first(where: { $0.isKeyWindow }),
                  let rootVC = window.rootViewController else {
                errorMessage = "Unable to present sign in. Please try again."
                loading = false
                return
            }
            var presentingVC = rootVC
            while let presented = presentingVC.presentedViewController {
                presentingVC = presented
            }

            let provider = OAuthProvider(providerID: "microsoft.com")
            provider.scopes = ["email", "profile", "openid"]
            // prompt=select_account forces the account picker even if already signed in
            provider.customParameters = ["prompt": "select_account"]

            do {
                // Firebase presents Microsoft's OAuth web page via ASWebAuthenticationSession.
                // The callback fires after the user signs in or cancels.
                let credential = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthCredential, Error>) in
                    provider.getCredentialWith(presentingVC as? AuthUIDelegate) { credential, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let credential {
                            continuation.resume(returning: credential)
                        } else {
                            continuation.resume(throwing: NSError(
                                domain: "LuniferSignin",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "No credential returned."]
                            ))
                        }
                    }
                }
                let authResult = try await Auth.auth().signIn(with: credential)
                await onSignedIn(authResult.additionalUserInfo?.isNewUser ?? false)
            } catch {
                errorMessage = friendlySigninError(error)
            }
            loading = false
        }
    }

    private func handleGoogleSignIn() {
        guard agreedToTerms else {
            withAnimation { errorMessage = "Please agree to the Terms of Service and Privacy Policy to continue." }
            return
        }
        Task { @MainActor in
            loading = true
            errorMessage = nil
            do {
                guard let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }),
                      let window = windowScene.windows.first(where: { $0.isKeyWindow }),
                      let rootVC = window.rootViewController else {
                    errorMessage = "Unable to present sign in. Please try again."
                    loading = false
                    return
                }
                // Walk up to the topmost presented view controller
                var presentingVC = rootVC
                while let presented = presentingVC.presentedViewController {
                    presentingVC = presented
                }
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC)
                guard let idToken = result.user.idToken?.tokenString else {
                    errorMessage = "Something went wrong. Please try again."
                    loading = false
                    return
                }
                let credential = GoogleAuthProvider.credential(
                    withIDToken: idToken,
                    accessToken: result.user.accessToken.tokenString
                )
                let authResult = try await Auth.auth().signIn(with: credential)
                await onSignedIn(authResult.additionalUserInfo?.isNewUser ?? false)
            } catch {
                errorMessage = friendlySigninError(error)
            }
            loading = false
        }
    }
}

// ── MARK: Apple Sign-In helpers ──────────────────────────────
// Random nonce generation + SHA-256 hashing, as required by
// Firebase's Apple Sign-In integration. Reference:
//   https://firebase.google.com/docs/auth/ios/apple

private enum AppleSignInNonce {

    /// Generates a cryptographically secure random nonce of the given
    /// length. The character set matches Apple/Firebase's example.
    static func makeRandomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
        )
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with status \(status)")
            }
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    /// Returns the lowercase hex SHA-256 of the input string.
    static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

// ── MARK: Apple Sign-In coordinator ──────────────────────────
// Bridges ASAuthorizationController's delegate callbacks into a
// single async/await call. The coordinator keeps itself alive
// for the duration of the auth flow by being captured in the
// continuation's closure.

private final class AppleSignInCoordinator: NSObject,
                                            ASAuthorizationControllerDelegate,
                                            ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var controller: ASAuthorizationController?

    /// Performs the authorization flow and resumes with the resulting
    /// Apple ID credential, or throws if the user cancels or an error
    /// occurs.
    func perform(controller: ASAuthorizationController) async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.controller = controller
            controller.performRequests()
        }
    }

    // MARK: ASAuthorizationControllerDelegate

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { self.controller = nil }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: NSError(
                domain: "LuniferSignin.Apple",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected Apple credential type."]
            ))
            continuation = nil
            return
        }
        continuation?.resume(returning: credential)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        defer { self.controller = nil }
        continuation?.resume(throwing: error)
        continuation = nil
    }

    // MARK: ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Find the topmost active key window so Apple's sheet has a valid anchor.
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
        // Fallback: any window that exists. ASAuthorization requires a non-nil
        // anchor, so returning a placeholder is preferable to crashing.
        return UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first ?? UIWindow()
    }
}

// ── MARK: Preview ────────────────────────────────────────────

#Preview {
    LuniferSignin()
}
