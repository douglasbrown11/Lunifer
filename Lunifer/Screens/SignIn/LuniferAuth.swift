import SwiftUI
import UIKit
import FirebaseAuth
import GoogleSignIn

// ── MARK: Types ──────────────────────────────────────────────

private enum AuthMode {
    case signIn, create
}

// ── MARK: Error mapping ──────────────────────────────────────
// Mirrors the getFriendlyError() function in luniferAuth.jsx

private func friendlyAuthError(_ error: Error) -> String {
    let nsError = error as NSError

    // Google Sign In cancellation (kGIDSignInErrorDomain, code -5)
    if nsError.domain.contains("GIDSignIn") && nsError.code == -5 {
        return "Sign in was cancelled."
    }

    // Microsoft / ASWebAuthenticationSession cancellation
    if nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession" && nsError.code == 1 {
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

// ── MARK: LuniferAuth ────────────────────────────────────────

struct LuniferAuth: View {
    var onSignedIn: () -> Void = {}

    @State private var mode: AuthMode = .create
    @State private var email = ""
    @State private var password = ""
    @State private var loading = false
    @State private var errorMessage: String?

    private var canSubmit: Bool { !email.isEmpty && password.count >= 6 }

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
                    Button { handleEmailAuth() } label: {
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

                    // ── Google button ────────────────────────
                    Button { handleGoogleSignIn() } label: {
                        HStack(spacing: 10) {
                            GoogleLogoView()
                            Text("Continue with Google")
                                .font(.custom("DM Sans", size: 15))
                                .foregroundColor(Color.white.opacity(0.8))
                        }
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
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }

    // ── MARK: Actions ────────────────────────────────────────

    private func handleEmailAuth() {
        guard canSubmit else { return }
        Task { @MainActor in
            loading = true
            errorMessage = nil
            do {
                if mode == .create {
                    try await Auth.auth().createUser(withEmail: email, password: password)
                } else {
                    try await Auth.auth().signIn(withEmail: email, password: password)
                }
                onSignedIn()
            } catch {
                errorMessage = friendlyAuthError(error)
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
                                domain: "LuniferAuth",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "No credential returned."]
                            ))
                        }
                    }
                }
                try await Auth.auth().signIn(with: credential)
                onSignedIn()
            } catch {
                errorMessage = friendlyAuthError(error)
            }
            loading = false
        }
    }

    private func handleGoogleSignIn() {
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
                try await Auth.auth().signIn(with: credential)
                onSignedIn()
            } catch {
                errorMessage = friendlyAuthError(error)
            }
            loading = false
        }
    }
}

// ── MARK: Preview ────────────────────────────────────────────

#Preview {
    LuniferAuth()
}
