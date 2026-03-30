import Foundation
import AuthenticationServices
import CryptoKit

// ─────────────────────────────────────────────────────────────
// WhoopManager
// ─────────────────────────────────────────────────────────────
// Handles the full WHOOP OAuth 2.0 + PKCE flow and nightly
// sleep-need retrieval via the WHOOP Developer API.
//
// DATA FLOW:
//   connect()
//     → ASWebAuthenticationSession (OAuth consent)
//     → exchangeCodeForTokens()  → Keychain
//     → fetchSleepNeed()         → AppPreferencesStore + @Published
//
// SLEEP NEED FORMULA (from /v1/cycle response):
//   total_ms = baseline_milli
//            + need_from_sleep_debt_milli
//            + need_from_recent_strain_milli
//            - need_from_recent_nap_milli
//   hours    = total_ms / 3_600_000
//   clamped to [5, 12] hours
//
// REFRESH STRATEGY:
//   - Access token refreshed automatically when < 5 min to expiry
//   - refreshIfNeeded() called at app launch / dashboard appear
//     to silently re-sync if last sync was > 12 hours ago

// MARK: - Error

enum WhoopError: LocalizedError {
    case cancelled
    case missingAuthCode
    case invalidURL
    case noRefreshToken
    case notAuthenticated
    case noData
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .cancelled:          return "Authorization was cancelled."
        case .missingAuthCode:    return "No authorization code returned by WHOOP."
        case .invalidURL:         return "Could not construct the WHOOP API URL."
        case .noRefreshToken:     return "No refresh token available. Please reconnect WHOOP."
        case .notAuthenticated:   return "Not connected to WHOOP."
        case .noData:             return "No sleep data returned by WHOOP."
        case .httpError(let c):   return "WHOOP API returned HTTP \(c)."
        }
    }
}

// MARK: - Response Models

private struct WhoopTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int       // seconds
    let token_type: String
}

private struct WhoopCycleResponse: Decodable {
    let records: [WhoopCycle]
}

private struct WhoopCycle: Decodable {
    let score: WhoopCycleScore?
}

private struct WhoopCycleScore: Decodable {
    let sleep_needed: WhoopSleepNeeded?
}

private struct WhoopSleepNeeded: Decodable {
    let baseline_milli: Int
    let need_from_sleep_debt_milli: Int
    let need_from_recent_strain_milli: Int
    let need_from_recent_nap_milli: Int
}

// MARK: - WhoopManager

@MainActor
final class WhoopManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    static let shared = WhoopManager()

    // MARK: Published state

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var recommendedSleepHours: Double = 0
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var lastSyncDate: Date? = nil

    // MARK: Private

    private var authSession: ASWebAuthenticationSession?

    // MARK: - API Constants
    // Replace clientID and clientSecret with your actual WHOOP Developer credentials
    // from https://app.whoop.com/settings/developer

    private enum API {
        static let clientID     = "YOUR_WHOOP_CLIENT_ID"        // ← replace
        static let clientSecret = "YOUR_WHOOP_CLIENT_SECRET"    // ← replace
        static let redirectURI  = "lunifer://whoop/callback"
        static let authURL      = "https://api.prod.whoop.com/oauth/oauth2/auth"
        static let tokenURL     = "https://api.prod.whoop.com/oauth/oauth2/token"
        static let cycleURL     = "https://api.prod.whoop.com/developer/v1/cycle"
        static let scopes       = "read:sleep read:cycles offline"
    }

    // MARK: - Init

    override private init() {
        super.init()
        // Restore persisted state on launch
        let prefs = AppPreferencesStore.shared
        isConnected           = prefs.whoopConnected
        recommendedSleepHours = prefs.whoopRecommendedSleepHours
        lastSyncDate          = prefs.whoopLastSyncDate
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Connect

    /// Launches the OAuth consent flow. Throws WhoopError.cancelled silently
    /// (user just closed the sheet — no error message needed).
    func connect() async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        let verifier  = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let state     = UUID().uuidString

        // Build authorization URL
        guard var components = URLComponents(string: API.authURL) else {
            throw WhoopError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "client_id",             value: API.clientID),
            URLQueryItem(name: "redirect_uri",          value: API.redirectURI),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "scope",                 value: API.scopes),
            URLQueryItem(name: "state",                 value: state),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authURL = components.url else {
            throw WhoopError.invalidURL
        }

        // Run ASWebAuthenticationSession and await callback
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "lunifer"
            ) { url, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: WhoopError.cancelled)
                } else if let url = url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? WhoopError.missingAuthCode)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }

        // Extract authorization code from callback
        guard let components2 = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components2.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw WhoopError.missingAuthCode
        }

        // Exchange code for tokens, then fetch sleep need
        try await exchangeCodeForTokens(code: code, codeVerifier: verifier)
        try await fetchSleepNeed()
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws {
        guard let url = URL(string: API.tokenURL) else { throw WhoopError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type":    "authorization_code",
            "client_id":     API.clientID,
            "client_secret": API.clientSecret,
            "code":          code,
            "redirect_uri":  API.redirectURI,
            "code_verifier": codeVerifier
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw WhoopError.httpError(http.statusCode)
        }

        let tokenResponse = try JSONDecoder().decode(WhoopTokenResponse.self, from: data)

        // Persist tokens in Keychain
        KeychainHelper.save(tokenResponse.access_token,  forKey: KeychainHelper.Keys.whoopAccessToken)
        KeychainHelper.save(tokenResponse.refresh_token, forKey: KeychainHelper.Keys.whoopRefreshToken)

        // Store expiry timestamp
        let expiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        AppPreferencesStore.shared.whoopTokenExpiry = expiry
        AppPreferencesStore.shared.whoopConnected   = true
        isConnected = true
    }

    // MARK: - Refresh Token

    private func refreshAccessToken() async throws {
        guard let refreshToken = KeychainHelper.load(forKey: KeychainHelper.Keys.whoopRefreshToken),
              !refreshToken.isEmpty else {
            throw WhoopError.noRefreshToken
        }

        guard let url = URL(string: API.tokenURL) else { throw WhoopError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type":    "refresh_token",
            "client_id":     API.clientID,
            "client_secret": API.clientSecret,
            "refresh_token": refreshToken
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw WhoopError.httpError(http.statusCode)
        }

        let tokenResponse = try JSONDecoder().decode(WhoopTokenResponse.self, from: data)

        KeychainHelper.save(tokenResponse.access_token,  forKey: KeychainHelper.Keys.whoopAccessToken)
        KeychainHelper.save(tokenResponse.refresh_token, forKey: KeychainHelper.Keys.whoopRefreshToken)

        let expiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        AppPreferencesStore.shared.whoopTokenExpiry = expiry
    }

    // MARK: - Fetch Sleep Need

    /// Fetches the current cycle from WHOOP and calculates tonight's sleep need.
    /// Refreshes the access token if it's within 5 minutes of expiry.
    func fetchSleepNeed() async throws {
        guard isConnected else { throw WhoopError.notAuthenticated }

        // Refresh token proactively if expiring soon (< 5 min)
        let expiry = AppPreferencesStore.shared.whoopTokenExpiry
        if let expiry = expiry, expiry.timeIntervalSinceNow < 300 {
            try await refreshAccessToken()
        }

        guard let accessToken = KeychainHelper.load(forKey: KeychainHelper.Keys.whoopAccessToken),
              !accessToken.isEmpty else {
            throw WhoopError.notAuthenticated
        }

        guard var components = URLComponents(string: API.cycleURL) else {
            throw WhoopError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "limit", value: "1")]

        guard let url = components.url else { throw WhoopError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw WhoopError.httpError(http.statusCode)
        }

        let cycleResponse = try JSONDecoder().decode(WhoopCycleResponse.self, from: data)

        guard let cycle = cycleResponse.records.first,
              let score = cycle.score,
              let sleepNeeded = score.sleep_needed else {
            throw WhoopError.noData
        }

        // Total sleep need in milliseconds → hours
        let totalMs = sleepNeeded.baseline_milli
                    + sleepNeeded.need_from_sleep_debt_milli
                    + sleepNeeded.need_from_recent_strain_milli
                    - sleepNeeded.need_from_recent_nap_milli

        let rawHours = Double(max(totalMs, 0)) / 3_600_000.0

        // Clamp to a physiologically plausible range
        let hours = max(5.0, min(rawHours, 12.0))

        // Persist and publish
        AppPreferencesStore.shared.whoopRecommendedSleepHours = hours
        AppPreferencesStore.shared.whoopLastSyncDate = Date()
        recommendedSleepHours = hours
        lastSyncDate          = Date()
    }

    // MARK: - Background Refresh

    /// Call from app launch or dashboard appear. Silently re-syncs if last
    /// sync was more than 12 hours ago. Errors are swallowed — the cached
    /// value stays in place if the network is unavailable.
    func refreshIfNeeded() {
        guard isConnected else { return }
        let twelveHours: TimeInterval = 12 * 60 * 60
        if let last = lastSyncDate, Date().timeIntervalSince(last) < twelveHours { return }

        Task {
            do {
                try await fetchSleepNeed()
            } catch {
                // Non-critical — keep showing cached value
            }
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        KeychainHelper.delete(forKey: KeychainHelper.Keys.whoopAccessToken)
        KeychainHelper.delete(forKey: KeychainHelper.Keys.whoopRefreshToken)
        AppPreferencesStore.shared.resetWhoopData()
        isConnected           = false
        recommendedSleepHours = 0
        lastSyncDate          = nil
        errorMessage          = nil
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
            ?? ASPresentationAnchor()
        }
    }
}
