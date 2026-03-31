import Foundation
import Combine
import AuthenticationServices
import CryptoKit
import FirebaseAuth

enum WhoopError: LocalizedError {
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
        case .cancelled: return "Authorization was cancelled."
        case .missingAuthCode: return "No authorization code returned by WHOOP."
        case .invalidURL: return "Could not construct the WHOOP API URL."
        case .notAuthenticated: return "Sign in to Lunifer before connecting WHOOP."
        case .backendUnavailable: return "WHOOP backend is not configured yet."
        case .backendError(let message): return message
        case .noData: return "No sleep data returned by WHOOP."
        case .invalidResponse: return "WHOOP returned an invalid response."
        }
    }
}

private struct WhoopBackendStatusResponse: Decodable {
    let connected: Bool
    let recommendedSleepHours: Double?
    let lastSyncDate: String?
}

@MainActor
final class WhoopManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WhoopManager()

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var recommendedSleepHours: Double = 0
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var lastSyncDate: Date? = nil

    private var authSession: ASWebAuthenticationSession?

    private enum API {
        static let clientID = "42b74796-f1a2-449d-8ba4-372a7b9c66ca"
        static let redirectURI = "lunifer://whoop/callback"
        static let authURL = "https://api.prod.whoop.com/oauth/oauth2/auth"
        static let scopes = "read:sleep read:cycles offline"
    }

    private enum Backend {
        static let baseURL = "https://lunifer-whoop.dougiebrown516.workers.dev"
        static let exchangeCodePath = "/whoop/exchange-code"
        static let fetchSleepNeedPath = "/whoop/fetch-sleep-need"
        static let disconnectPath = "/whoop/disconnect"
    }

    override private init() {
        super.init()
        let prefs = AppPreferencesStore.shared
        isConnected = prefs.whoopConnected
        recommendedSleepHours = prefs.whoopRecommendedSleepHours
        lastSyncDate = prefs.whoopLastSyncDate
    }

    private var baseBackendURL: URL? {
        URL(string: Backend.baseURL)
    }

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

    func connect() async throws {
        guard Auth.auth().currentUser != nil else { throw WhoopError.notAuthenticated }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let state = UUID().uuidString

        guard var components = URLComponents(string: API.authURL) else {
            throw WhoopError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: API.clientID),
            URLQueryItem(name: "redirect_uri", value: API.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: API.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authURL = components.url else {
            throw WhoopError.invalidURL
        }

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

        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw WhoopError.missingAuthCode
        }

        let status: WhoopBackendStatusResponse = try await callBackend(
            path: Backend.exchangeCodePath,
            payload: [
                "code": code,
                "codeVerifier": verifier,
                "redirectURI": API.redirectURI
            ]
        )
        apply(status: status)
    }

    func fetchSleepNeed() async throws {
        let status: WhoopBackendStatusResponse = try await callBackend(
            path: Backend.fetchSleepNeedPath,
            payload: [:]
        )
        guard let hours = status.recommendedSleepHours, hours > 0 else {
            throw WhoopError.noData
        }
        apply(status: status)
    }

    func refreshIfNeeded() {
        guard isConnected else { return }
        let twelveHours: TimeInterval = 12 * 60 * 60
        if let last = lastSyncDate, Date().timeIntervalSince(last) < twelveHours { return }

        Task {
            do {
                try await fetchSleepNeed()
            } catch {
                // Keep cached data if refresh fails.
            }
        }
    }

    func disconnect() {
        Task {
            do {
                let _: WhoopBackendStatusResponse = try await callBackend(
                    path: Backend.disconnectPath,
                    payload: [:]
                )
            } catch {
                // Local cleanup should still happen even if the backend call fails.
            }
        }

        AppPreferencesStore.shared.resetWhoopData()
        isConnected = false
        recommendedSleepHours = 0
        lastSyncDate = nil
        errorMessage = nil
    }

    private func apply(status: WhoopBackendStatusResponse) {
        let hours = max(0, status.recommendedSleepHours ?? 0)
        let syncDate = status.lastSyncDate.flatMap(Self.iso8601.date(from:))

        AppPreferencesStore.shared.whoopConnected = status.connected
        AppPreferencesStore.shared.whoopRecommendedSleepHours = hours
        AppPreferencesStore.shared.whoopLastSyncDate = syncDate

        isConnected = status.connected
        recommendedSleepHours = hours
        lastSyncDate = syncDate
    }

    private func callBackend<Response: Decodable>(path: String, payload: [String: Any]) async throws -> Response {
        guard let user = Auth.auth().currentUser else {
            throw WhoopError.notAuthenticated
        }
        guard let baseURL = baseBackendURL else {
            throw WhoopError.backendUnavailable
        }

        let idToken = try await user.getIDToken()
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WhoopError.invalidResponse
        }

        if !(200...299).contains(http.statusCode) {
            let backendMessage = (try? JSONDecoder().decode(BackendErrorResponse.self, from: data))?.error
            throw WhoopError.backendError(backendMessage ?? "WHOOP backend returned HTTP \(http.statusCode).")
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw WhoopError.invalidResponse
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let keyWindow = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
            if let scene = scenes.first {
                return ASPresentationAnchor(windowScene: scene)
            }
            if #available(iOS 26.0, *) {
                fatalError("Unable to find a UIWindowScene for ASWebAuthenticationSession presentation.")
            } else {
                return ASPresentationAnchor()
            }
        }
    }

    private struct BackendErrorResponse: Decodable {
        let error: String
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
