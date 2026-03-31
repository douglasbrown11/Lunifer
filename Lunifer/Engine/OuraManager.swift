import Foundation
import Combine
import AuthenticationServices
import CryptoKit
import FirebaseAuth

enum OuraError: LocalizedError {
    case cancelled
    case missingAuthCode
    case invalidURL
    case notAuthenticated
    case backendUnavailable
    case backendError(String)
    case noData
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .cancelled:              return "Authorization was cancelled."
        case .missingAuthCode:        return "No authorization code returned by Oura."
        case .invalidURL:             return "Could not construct the Oura API URL."
        case .notAuthenticated:       return "Sign in to Lunifer before connecting Oura."
        case .backendUnavailable:     return "Oura backend is not configured yet."
        case .backendError(let msg):  return msg
        case .noData:                 return "No sleep data returned by Oura."
        case .invalidResponse:        return "Oura returned an invalid response."
        }
    }
}

private struct OuraBackendStatusResponse: Decodable {
    let connected: Bool
    let recommendedSleepHours: Double?
    let lastSyncDate: String?
}

@MainActor
final class OuraManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OuraManager()

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var recommendedSleepHours: Double = 0
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var lastSyncDate: Date? = nil

    private var authSession: ASWebAuthenticationSession?

    private enum API {
        // Replace with your Oura Developer app Client ID from cloud.ouraring.com/oauth/apps
        static let clientID   = "YOUR_OURA_CLIENT_ID"
        static let redirectURI = "lunifer://oura/callback"
        static let authURL    = "https://cloud.ouraring.com/oauth/authorize"
        // Oura v2 scopes needed for sleep data
        static let scopes     = "daily personal"
    }

    private enum Backend {
        static let baseURL           = "https://lunifer-whoop.dougiebrown516.workers.dev"
        static let exchangeCodePath  = "/oura/exchange-code"
        static let fetchSleepPath    = "/oura/fetch-sleep"
        static let disconnectPath    = "/oura/disconnect"
    }

    override private init() {
        super.init()
        let prefs = AppPreferencesStore.shared
        isConnected           = prefs.ouraConnected
        recommendedSleepHours = prefs.ouraRecommendedSleepHours
        lastSyncDate          = prefs.ouraLastSyncDate
    }

    private var baseBackendURL: URL? { URL(string: Backend.baseURL) }

    // MARK: - Connect (standard OAuth 2.0 — no PKCE, secret lives on the Worker)

    func connect() async throws {
        guard Auth.auth().currentUser != nil else { throw OuraError.notAuthenticated }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard var components = URLComponents(string: API.authURL) else {
            throw OuraError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "client_id",     value: API.clientID),
            URLQueryItem(name: "redirect_uri",  value: API.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope",         value: API.scopes),
            URLQueryItem(name: "state",         value: UUID().uuidString)
        ]
        guard let authURL = components.url else { throw OuraError.invalidURL }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "lunifer"
            ) { url, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: OuraError.cancelled)
                } else if let url = url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? OuraError.missingAuthCode)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }

        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value
        else { throw OuraError.missingAuthCode }

        let status: OuraBackendStatusResponse = try await callBackend(
            path: Backend.exchangeCodePath,
            payload: ["code": code, "redirectURI": API.redirectURI]
        )
        apply(status: status)
    }

    // MARK: - Fetch sleep recommendation

    func fetchSleepRecommendation() async throws {
        let status: OuraBackendStatusResponse = try await callBackend(
            path: Backend.fetchSleepPath,
            payload: [:]
        )
        guard let hours = status.recommendedSleepHours, hours > 0 else {
            throw OuraError.noData
        }
        apply(status: status)
    }

    // MARK: - Refresh if stale (called on SleepInsights appear)

    func refreshIfNeeded() {
        guard isConnected else { return }
        let twelveHours: TimeInterval = 12 * 60 * 60
        if let last = lastSyncDate, Date().timeIntervalSince(last) < twelveHours { return }
        Task {
            do { try await fetchSleepRecommendation() } catch { /* keep cached */ }
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        Task {
            do {
                let _: OuraBackendStatusResponse = try await callBackend(
                    path: Backend.disconnectPath,
                    payload: [:]
                )
            } catch { /* local cleanup still happens */ }
        }
        AppPreferencesStore.shared.resetOuraData()
        isConnected           = false
        recommendedSleepHours = 0
        lastSyncDate          = nil
        errorMessage          = nil
    }

    // MARK: - Private helpers

    private func apply(status: OuraBackendStatusResponse) {
        let hours    = max(0, status.recommendedSleepHours ?? 0)
        let syncDate = status.lastSyncDate.flatMap(Self.iso8601.date(from:))

        AppPreferencesStore.shared.ouraConnected               = status.connected
        AppPreferencesStore.shared.ouraRecommendedSleepHours   = hours
        AppPreferencesStore.shared.ouraLastSyncDate            = syncDate

        isConnected           = status.connected
        recommendedSleepHours = hours
        lastSyncDate          = syncDate
    }

    private func callBackend<Response: Decodable>(path: String, payload: [String: Any]) async throws -> Response {
        guard let user = Auth.auth().currentUser else { throw OuraError.notAuthenticated }
        guard let baseURL = baseBackendURL        else { throw OuraError.backendUnavailable }

        let idToken = try await user.getIDToken()
        let url     = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)",   forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OuraError.invalidResponse }

        if !(200...299).contains(http.statusCode) {
            let msg = (try? JSONDecoder().decode(BackendErrorResponse.self, from: data))?.error
            throw OuraError.backendError(msg ?? "Oura backend returned HTTP \(http.statusCode).")
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OuraError.invalidResponse
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let keyWindow = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
            if let scene = scenes.first { return ASPresentationAnchor(windowScene: scene) }
            if #available(iOS 26.0, *) {
                fatalError("Unable to find a UIWindowScene for OuraManager OAuth presentation.")
            } else {
                return ASPresentationAnchor()
            }
        }
    }

    private struct BackendErrorResponse: Decodable { let error: String }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
