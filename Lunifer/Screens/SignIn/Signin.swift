import SwiftUI
import UIKit
import FirebaseAuth
import GoogleSignIn
import AuthenticationServices
import CryptoKit

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
    private var msSignInSession: ASWebAuthenticationSession? = nil
    private var msSignInCoordinator: MicrosoftSignInCoordinator? = nil

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
    // Uses direct PKCE OAuth with Microsoft's endpoint via ASWebAuthenticationSession,
    // bypassing Firebase's /__/auth/handler redirect page entirely. The old approach
    // (OAuthProvider.getCredentialWith(nil)) routed through lunifer-ce086.firebaseapp.com
    // which caused the recurring "missing initial state / sessionStorage" error on iOS.

    func handleMicrosoftSignIn(
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
            resetMessage = nil

            let clientID    = "55d084c8-c89d-4023-95c9-c20ac76a9a30"
            let redirectURI = "msauth.Dream-AI.Lunifer://auth"

            // PKCE — code verifier + SHA-256 challenge
            var buffer = [UInt8](repeating: 0, count: 64)
            _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
            let verifier = Data(buffer).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")

            var comps = URLComponents(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!
            comps.queryItems = [
                URLQueryItem(name: "client_id",             value: clientID),
                URLQueryItem(name: "response_type",         value: "code"),
                URLQueryItem(name: "redirect_uri",          value: redirectURI),
                URLQueryItem(name: "scope",                 value: "openid profile email"),
                URLQueryItem(name: "response_mode",         value: "query"),
                URLQueryItem(name: "state",                 value: UUID().uuidString),
                URLQueryItem(name: "code_challenge",        value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "prompt",                value: "select_account")
            ]
            guard let authURL = comps.url else {
                errorMessage = "Something went wrong. Please try again."
                loading = false
                return
            }

            do {
                let coordinator = MicrosoftSignInCoordinator()
                let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
                    let session = ASWebAuthenticationSession(
                        url: authURL,
                        callbackURLScheme: "msauth.Dream-AI.Lunifer"
                    ) { url, error in
                        if let asError = error as? ASWebAuthenticationSessionError,
                           asError.code == .canceledLogin {
                            continuation.resume(throwing: CancellationError())
                        } else if let url = url {
                            continuation.resume(returning: url)
                        } else {
                            continuation.resume(throwing: error ?? NSError(
                                domain: "LuniferSignin", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Microsoft sign-in failed."]))
                        }
                    }
                    session.presentationContextProvider = coordinator
                    session.prefersEphemeralWebBrowserSession = false
                    msSignInSession     = session
                    msSignInCoordinator = coordinator
                    session.start()
                }
                msSignInSession     = nil
                msSignInCoordinator = nil

                guard let callbackComps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = callbackComps.queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    errorMessage = "Something went wrong. Please try again."
                    loading = false
                    return
                }

                // Exchange auth code for tokens (PKCE — no client secret on device)
                var tokenRequest = URLRequest(url: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!)
                tokenRequest.httpMethod = "POST"
                tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                let body: [String: String] = [
                    "client_id":     clientID,
                    "grant_type":    "authorization_code",
                    "code":          code,
                    "redirect_uri":  redirectURI,
                    "code_verifier": verifier,
                    "scope":         "openid profile email"
                ]
                tokenRequest.httpBody = body
                    .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
                    .joined(separator: "&")
                    .data(using: .utf8)

                let (data, _) = try await URLSession.shared.data(for: tokenRequest)

                struct MSTokenResponse: Decodable {
                    let access_token: String
                    let id_token: String?
                }
                let tokens = try JSONDecoder().decode(MSTokenResponse.self, from: data)
                guard let idToken = tokens.id_token else {
                    errorMessage = "Something went wrong. Please try again."
                    loading = false
                    return
                }

                let credential = OAuthProvider.credential(
                    providerID: AuthProviderID(rawValue: "microsoft.com"),
                    idToken: idToken,
                    rawNonce: "",
                    accessToken: tokens.access_token
                )
                let authResult = try await Auth.auth().signIn(with: credential)
                await onSignedIn(authResult.additionalUserInfo?.isNewUser ?? false)
            } catch is CancellationError {
                // User cancelled — no error message needed
            } catch {
                errorMessage = friendlySigninError(error)
            }
            loading = false
        }
    }

    // ── Google sign-in ───────────────────────────────────────

    func handleGoogleSignIn(
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

// ── MARK: Microsoft Sign-In coordinator ──────────────────────

private final class MicrosoftSignInCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow }) ?? UIWindow()
    }
}
