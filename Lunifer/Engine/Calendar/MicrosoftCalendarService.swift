import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit
import UIKit

// ─────────────────────────────────────────────────────────────
// MicrosoftCalendarService
// ─────────────────────────────────────────────────────────────
// Reads the user's Outlook / Microsoft 365 calendar directly from
// Microsoft Graph, so events are available even when the account is
// NOT synced into the iOS system calendar (EventKit can't see those).
//
// FLOW (mirrors the WHOOP/Oura OAuth pattern):
//   • connect() runs a PKCE OAuth via ASWebAuthenticationSession,
//     requesting the `Calendars.Read` + `offline_access` scopes, then
//     stores the access token, refresh token, and expiry in the Keychain.
//   • events(from:to:) returns the user's events for a date range, used
//     by CalendarManager when the user's chosen provider is "outlook".
//   • The refresh token is the only persistent credential — the user taps
//     "Allow" once, and the service silently refreshes the short-lived
//     access token from then on. Nothing is shown to or typed by the user.
//
// Declined / all-day events are flagged on the returned CalendarEvent so
// the alarm baseline can filter them, matching the EventKit path.
//
// Setup required (outside this file):
//   • Azure app registration (App ID 55d084c8-c89d-4023-95c9-c20ac76a9a30)
//     must list the `Calendars.Read` delegated Graph permission and the
//     `msauth.Dream-AI.Lunifer://auth` redirect URI (already used for sign-in).

@MainActor
final class MicrosoftCalendarService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding, CalendarEventSource {

    static let shared = MicrosoftCalendarService()

    @Published private(set) var isConnectedFlag: Bool = false

    private var authSession: ASWebAuthenticationSession?

    private enum API {
        static let clientID    = "55d084c8-c89d-4023-95c9-c20ac76a9a30"
        static let redirectURI = "msauth.Dream-AI.Lunifer://auth"
        static let callbackScheme = "msauth.Dream-AI.Lunifer"
        static let authURL     = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
        static let tokenURL    = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
        // offline_access yields a refresh token; Calendars.Read grants calendar reads.
        static let scope       = "openid profile offline_access Calendars.Read"
        static let calendarView = "https://graph.microsoft.com/v1.0/me/calendarView"
    }

    override private init() {
        super.init()
        isConnectedFlag = KeychainHelper.load(forKey: KeychainHelper.Keys.msCalendarRefreshToken) != nil
    }

    // MARK: - CalendarEventSource

    func isConnected() -> Bool { isConnectedFlag }

    // MARK: - Connect / disconnect

    /// Runs the PKCE OAuth consent and persists the resulting tokens.
    /// Call when the user selects "Outlook" as their calendar provider.
    func connect() async {
        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        var comps = URLComponents(string: API.authURL)!
        comps.queryItems = [
            URLQueryItem(name: "client_id",             value: API.clientID),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "redirect_uri",          value: API.redirectURI),
            URLQueryItem(name: "scope",                 value: API.scope),
            URLQueryItem(name: "response_mode",         value: "query"),
            URLQueryItem(name: "state",                 value: UUID().uuidString),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt",                value: "select_account")
        ]
        guard let authURL = comps.url else { return }

        do {
            let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: API.callbackScheme
                ) { url, error in
                    if let asError = error as? ASWebAuthenticationSessionError,
                       asError.code == .canceledLogin {
                        continuation.resume(throwing: CancellationError())
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: error ?? CancellationError())
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self.authSession = session
                session.start()
            }
            self.authSession = nil

            guard let callbackComps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = callbackComps.queryItems?.first(where: { $0.name == "code" })?.value else {
                return
            }

            try await exchangeAuthCode(code, codeVerifier: verifier)
            isConnectedFlag = true
            print("✅ Outlook calendar connected")
        } catch is CancellationError {
            // User cancelled — nothing to do.
        } catch {
            print("❌ Outlook calendar connect failed: \(error.localizedDescription)")
        }
    }

    /// Clears stored Microsoft calendar tokens. Lunifer reverts to having no
    /// Outlook events (alarm falls back to historical pattern / 8 AM).
    func disconnect() {
        KeychainHelper.delete(forKey: KeychainHelper.Keys.msCalendarAccessToken)
        KeychainHelper.delete(forKey: KeychainHelper.Keys.msCalendarRefreshToken)
        KeychainHelper.delete(forKey: KeychainHelper.Keys.msCalendarTokenExpiry)
        isConnectedFlag = false
    }

    /// Nonisolated wipe for AccountDataManager sign-out / delete-account cleanup.
    nonisolated static func clearStoredData() {
        KeychainHelper.delete(forKey: KeychainHelper.Keys.msCalendarAccessToken)
        KeychainHelper.delete(forKey: KeychainHelper.Keys.msCalendarRefreshToken)
        KeychainHelper.delete(forKey: KeychainHelper.Keys.msCalendarTokenExpiry)
    }

    // MARK: - Event fetch

    func events(from start: Date, to end: Date) async -> [CalendarEvent] {
        guard let accessToken = await validAccessToken() else { return [] }

        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(identifier: "UTC")
        var comps = URLComponents(string: API.calendarView)!
        comps.queryItems = [
            URLQueryItem(name: "startDateTime", value: iso.string(from: start)),
            URLQueryItem(name: "endDateTime",   value: iso.string(from: end)),
            URLQueryItem(name: "$orderby",      value: "start/dateTime"),
            URLQueryItem(name: "$top",          value: "50")
        ]
        guard let url = comps.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        // Ask Graph to return all event times already converted to UTC so our
        // single UTC parser below is correct regardless of the event's own zone.
        request.setValue("outlook.timezone=\"UTC\"", forHTTPHeaderField: "Prefer")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            let decoded = try JSONDecoder().decode(GraphEventsResponse.self, from: data)
            return decoded.value.compactMap(Self.mapToCalendarEvent)
        } catch {
            print("❌ Graph calendar fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Token handling

    /// Returns a valid (refreshed if needed) access token, or nil if not connected.
    private func validAccessToken() async -> String? {
        guard let refreshToken = KeychainHelper.load(forKey: KeychainHelper.Keys.msCalendarRefreshToken) else {
            return nil
        }

        // Reuse the cached access token while it's still valid (60s safety buffer).
        if let token = KeychainHelper.load(forKey: KeychainHelper.Keys.msCalendarAccessToken),
           let expiryStr = KeychainHelper.load(forKey: KeychainHelper.Keys.msCalendarTokenExpiry),
           let expiry = TimeInterval(expiryStr),
           Date().timeIntervalSince1970 < expiry - 60 {
            return token
        }

        // Otherwise refresh.
        do {
            try await refresh(using: refreshToken)
            return KeychainHelper.load(forKey: KeychainHelper.Keys.msCalendarAccessToken)
        } catch {
            print("❌ Graph token refresh failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func exchangeAuthCode(_ code: String, codeVerifier: String) async throws {
        try await postToken(body: [
            "client_id":     API.clientID,
            "grant_type":    "authorization_code",
            "code":          code,
            "redirect_uri":  API.redirectURI,
            "code_verifier": codeVerifier,
            "scope":         API.scope
        ])
    }

    private func refresh(using refreshToken: String) async throws {
        try await postToken(body: [
            "client_id":     API.clientID,
            "grant_type":    "refresh_token",
            "refresh_token": refreshToken,
            "redirect_uri":  API.redirectURI,
            "scope":         API.scope
        ])
    }

    /// POSTs the token endpoint and persists access/refresh/expiry to the Keychain.
    private func postToken(body: [String: String]) async throws {
        var request = URLRequest(url: URL(string: API.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "MicrosoftCalendarService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Token request failed."])
        }
        let tokens = try JSONDecoder().decode(MSTokenResponse.self, from: data)

        KeychainHelper.save(tokens.access_token, forKey: KeychainHelper.Keys.msCalendarAccessToken)
        if let refresh = tokens.refresh_token {
            // Microsoft rotates refresh tokens; keep the latest. If absent, keep the old one.
            KeychainHelper.save(refresh, forKey: KeychainHelper.Keys.msCalendarRefreshToken)
        }
        let expiry = Date().timeIntervalSince1970 + Double(tokens.expires_in ?? 3600)
        KeychainHelper.save(String(expiry), forKey: KeychainHelper.Keys.msCalendarTokenExpiry)
    }

    // MARK: - Presentation anchor

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let keyWindow = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
            if let scene = scenes.first { return ASPresentationAnchor(windowScene: scene) }
            return ASPresentationAnchor()
        }
    }

    // MARK: - Mapping

    private static func mapToCalendarEvent(_ event: GraphEvent) -> CalendarEvent? {
        guard let startStr = event.start?.dateTime,
              let start = parseGraphDate(startStr) else { return nil }
        let end = event.end?.dateTime.flatMap(parseGraphDate) ?? start

        return CalendarEvent(
            id: event.id ?? UUID().uuidString,
            title: event.subject ?? "Untitled",
            startDate: start,
            endDate: end,
            isAllDay: event.isAllDay ?? false,
            calendarTitle: "Outlook",
            calendarColor: Color(red: 0.627, green: 0.471, blue: 1.0),
            location: event.location?.displayName,
            notes: nil,
            isDeclinedByUser: (event.responseStatus?.response ?? "").lowercased() == "declined"
        )
    }

    private static func parseGraphDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    // MARK: - PKCE helpers

    private static func makeCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return base64URL(Data(buffer))
    }

    private static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Graph / token response models

private struct MSTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
}

private struct GraphEventsResponse: Decodable {
    let value: [GraphEvent]
}

private struct GraphEvent: Decodable {
    let id: String?
    let subject: String?
    let isAllDay: Bool?
    let start: GraphDateTime?
    let end: GraphDateTime?
    let location: GraphLocation?
    let responseStatus: GraphResponseStatus?
}

private struct GraphDateTime: Decodable {
    let dateTime: String?
    let timeZone: String?
}

private struct GraphLocation: Decodable {
    let displayName: String?
}

private struct GraphResponseStatus: Decodable {
    let response: String?
}
