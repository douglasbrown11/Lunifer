import SwiftUI
import UIKit
import FirebaseAuth
import GoogleSignIn
import AuthenticationServices
import CryptoKit
import Combine

// ── MARK: Types ──────────────────────────────────────────────

enum SigninMode {
    case signIn, create
}

// ── MARK: Error mapping ──────────────────────────────────────
// Mirrors the getFriendlyError() function in luniferAuth.jsx

func friendlySigninError(_ error: Error) -> String {
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

// ── MARK: SigninBackend ──────────────────────────────────────
// Owns all auth state and every sign-in action. The view observes
// loading / errorMessage / resetMessage and calls the handle* methods.

@MainActor
final class SigninBackend: ObservableObject {
    @Published var loading = false
    @Published var errorMessage: String? = nil
    @Published var resetMessage: String? = nil

    // Held alive for the duration of their respective auth flows
    private var currentAppleNonce: String? = nil
    /// Retained for the duration of the Firebase-managed Microsoft OAuth flow so
    /// the provider (and its presented web session) isn't deallocated mid-sign-in.
    private var msOAuthProvider: OAuthProvider? = nil

    // ── Email / password ─────────────────────────────────────

    func handleEmailSignin(
        email: String,
        password: String,
        mode: SigninMode,
        agreedToTerms: Bool,
        onSignedIn: @escaping (_ isNewUser: Bool) async -> Void
    ) {
        guard !email.isEmpty && password.count >= 6 else { return }
        guard agreedToTerms else {
            withAnimation { errorMessage = "Please agree to the Terms of Service and Privacy Policy to continue." }
            return
        }
        Task { @MainActor in
            loading = true
            errorMessage = nil
            resetMessage = nil
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

    // ── Forgot password ──────────────────────────────────────

    func handleForgotPassword(email: String) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            withAnimation { errorMessage = "Enter your email address above, then tap Forgot password." }
            return
        }
        Task { @MainActor in
            loading = true
            errorMessage = nil
            resetMessage = nil
            do {
                try await Auth.auth().sendPasswordReset(withEmail: trimmedEmail)
                withAnimation { resetMessage = "Reset link sent to \(trimmedEmail). Check your inbox." }
            } catch {
                withAnimation { errorMessage = friendlySigninError(error) }
            }
            loading = false
        }
    }

    // ── Apple sign-in ────────────────────────────────────────
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

    func handleAppleSignIn(
        agreedToTerms: Bool,
        onSignedIn: @escaping (_ isNewUser: Bool) async -> Void
    ) {
        guard agreedToTerms else {
            withAnimation { errorMessage = "Please agree to the Terms of Service and Privacy Policy to continue." }
            return
        }
        Task { @MainActor in
            loading = true
            errorMessage = nil

            let rawNonce = AppleSignInNonce.makeRandomNonce()
            currentAppleNonce = rawNonce

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleSignInNonce.sha256(rawNonce)

            let coordinator = AppleSignInCoordinator()
            let controller  = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = coordinator
            controller.presentationContextProvider = coordinator

            do {
                let credential = try await coordinator.perform(controller: controller)

                guard let identityTokenData   = credential.identityToken,
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

    // ── Microsoft sign-in ────────────────────────────────────
    // Uses Firebase's MANAGED OAuth flow (`OAuthProvider(providerID:"microsoft.com")`
    // + getCredentialWith). This is the only path Firebase accepts for Microsoft —
    // a generic OAuth provider — because Firebase will not validate a self-obtained
    // Microsoft id_token via signInWithIdp (it returns INVALID_CREDENTIAL_OR_PROVIDER_ID,
    // even though the token is valid). Only Google/Apple accept manual id_tokens.
    //
    // The managed flow redirects through https://lunifer-ce086.firebaseapp.com/__/auth/handler
    // and back into the app. That callback is completed by the AppDelegate's
    // application(_:open:) (see App.swift) forwarding to Auth.auth().canHandle(url).
    // Without an AppDelegate, GoogleUtilities' swizzler can't hook the callback,
    // which is what produced the earlier "missing initial state / sessionStorage" error.

    func handleMicrosoftSignIn(
        calendarChoice: String = "",
        agreedToTerms: Bool,
        onSignedIn: @escaping (_ isNewUser: Bool) async -> Void
    ) {
        guard agreedToTerms else {
            withAnimation { errorMessage = "Please agree to the Terms of Service and Privacy Policy to continue." }
            return
        }
        // `calendarChoice` is accepted for call-site symmetry with the Google
        // handler. Outlook calendar access is connected separately (post-auth) from
        // the survey via `MicrosoftCalendarService.connect()`, so it is not requested
        // here — folding Graph scopes into the Firebase auth request breaks it.
        _ = calendarChoice

        let provider = OAuthProvider(providerID: "microsoft.com")
        // select_account lets the user pick which Microsoft account to use.
        provider.customParameters = ["prompt": "select_account"]
        // Retain the provider for the duration of the presented web flow.
        msOAuthProvider = provider

        Task { @MainActor in
            loading = true
            errorMessage = nil
            resetMessage = nil

            do {
                // Passing nil for the UIDelegate lets Firebase present its own
                // ASWebAuthenticationSession from the key window.
                let credential: AuthCredential = try await withCheckedThrowingContinuation { continuation in
                    provider.getCredentialWith(nil) { credential, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let credential {
                            continuation.resume(returning: credential)
                        } else {
                            continuation.resume(throwing: NSError(
                                domain: "LuniferSignin", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Microsoft sign-in failed."]))
                        }
                    }
                }

                let authResult = try await Auth.auth().signIn(with: credential)
                msOAuthProvider = nil
                await onSignedIn(authResult.additionalUserInfo?.isNewUser ?? false)
            } catch {
                msOAuthProvider = nil
                let nsError = error as NSError
                // Treat an explicit web-session cancel as a silent no-op.
                let cancelled =
                    (error is CancellationError) ||
                    (nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession" && nsError.code == 1) ||
                    (nsError.domain == AuthErrorDomain && nsError.code == AuthErrorCode.webContextCancelled.rawValue)
                if !cancelled {
                    // Log the raw error so any residual Firebase/Microsoft issue is
                    // visible in the Xcode console rather than hidden behind the
                    // friendly message.
                    print("❌ Microsoft sign-in error: \(error) — \(nsError.userInfo)")
                    errorMessage = friendlySigninError(error)
                }
            }
            loading = false
        }
    }

    // ── Google sign-in ───────────────────────────────────────

    func handleGoogleSignIn(
        calendarChoice: String = "",
        agreedToTerms: Bool,
        onSignedIn: @escaping (_ isNewUser: Bool) async -> Void
    ) {
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
                // When the user pre-selected Google Calendar, request the least-privilege
                // event + calendar-list scopes in this same sign-in so they authorize Google
                // only once (auth + calendar together). The granted scope makes
                // GoogleCalendarService.isConnected() true, so the survey's post-auth
                // connect() no-ops rather than prompting a second time.
                let additionalScopes = calendarChoice == "google" ? GoogleCalendarService.scopes : nil
                let result = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: presentingVC,
                    hint: nil,
                    additionalScopes: additionalScopes
                )
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

    // ── Re-authentication for account deletion ───────────────
    // Sensitive operations (deleting the account) require a recent login.
    // These mirror the sign-in handlers above but call user.reauthenticate
    // instead of Auth.signIn, so LuniferSettings can re-verify the user across
    // ALL providers — not just email/password — before deleting the account.
    // Each throws CancellationError when the user backs out so the caller can
    // abort silently without showing an error.

    func reauthenticateGoogle() async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "LuniferSignin", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No signed-in user."])
        }
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              let rootVC = window.rootViewController else {
            throw NSError(domain: "LuniferSignin", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to present sign in."])
        }
        var presentingVC = rootVC
        while let presented = presentingVC.presentedViewController { presentingVC = presented }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC)
            guard let idToken = result.user.idToken?.tokenString else {
                throw NSError(domain: "LuniferSignin", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Missing Google ID token."])
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            try await user.reauthenticate(with: credential)
        } catch let e as NSError where e.domain.contains("GIDSignIn") && e.code == -5 {
            throw CancellationError()
        }
    }

    func reauthenticateApple() async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "LuniferSignin", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No signed-in user."])
        }
        let rawNonce = AppleSignInNonce.makeRandomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleSignInNonce.sha256(rawNonce)

        let coordinator = AppleSignInCoordinator()
        let controller  = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = coordinator
        controller.presentationContextProvider = coordinator

        do {
            let credential = try await coordinator.perform(controller: controller)
            guard let tokenData = credential.identityToken,
                  let tokenString = String(data: tokenData, encoding: .utf8) else {
                throw NSError(domain: "LuniferSignin", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Missing Apple identity token."])
            }
            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: tokenString,
                rawNonce: rawNonce,
                fullName: credential.fullName
            )
            try await user.reauthenticate(with: firebaseCredential)
        } catch let e as ASAuthorizationError where e.code == .canceled {
            throw CancellationError()
        }
    }

    func reauthenticateMicrosoft() async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "LuniferSignin", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No signed-in user."])
        }
        // Use Firebase's managed OAuth flow (same reason as handleMicrosoftSignIn):
        // Firebase rejects a self-obtained Microsoft id_token, so we let it run the
        // OAuth flow through its handler and hand back a credential it trusts.
        let provider = OAuthProvider(providerID: "microsoft.com")
        provider.customParameters = ["prompt": "login"]
        msOAuthProvider = provider
        defer { msOAuthProvider = nil }

        let credential: AuthCredential = try await withCheckedThrowingContinuation { continuation in
            provider.getCredentialWith(nil) { credential, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let credential {
                    continuation.resume(returning: credential)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "LuniferSignin", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Microsoft sign-in failed."]))
                }
            }
        }
        try await user.reauthenticate(with: credential)
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
    /// Apple ID credential, or throws if the user cancels or an error occurs.
    func perform(controller: ASAuthorizationController) async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.controller   = controller
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
        // Fallback: any window that exists.
        return UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first ?? UIWindow()
    }
}
