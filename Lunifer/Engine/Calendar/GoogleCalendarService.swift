import Foundation
import SwiftUI
import Combine
import UIKit
import GoogleSignIn

// ─────────────────────────────────────────────────────────────
// GoogleCalendarService
// ─────────────────────────────────────────────────────────────
// Reads the user's Google Calendar directly from the Google Calendar
// API, so events are available even when the account is NOT added to
// the iOS system calendar (EventKit can't see those).
//
// Uses the GoogleSignIn SDK that the app already ships with. The SDK
// handles token storage and refresh, so this service only needs to:
//   • connect() — obtain the read-only calendar scope (incremental
//     consent on top of whatever Google session already exists, or a
//     fresh Google sign-in if there isn't one).
//   • events(from:to:) — fetch the user's events for a date range.
//
// Declined / all-day events are flagged on the returned CalendarEvent so
// the alarm baseline can filter them, matching the EventKit path.
//
// Setup required (outside this file):
//   • The Google Cloud OAuth consent screen must list the
//     `calendar.events.readonly` scope. No client secret is needed on device.

@MainActor
final class GoogleCalendarService: NSObject, ObservableObject, CalendarEventSource {

    static let shared = GoogleCalendarService()

    static let scope = "https://www.googleapis.com/auth/calendar.events.readonly"
    private static let eventsURL = "https://www.googleapis.com/calendar/v3/calendars/primary/events"

    private override init() { super.init() }

    // MARK: - CalendarEventSource

    /// Connected when the current Google session has granted the calendar scope.
    func isConnected() -> Bool {
        GIDSignIn.sharedInstance.currentUser?.grantedScopes?.contains(Self.scope) ?? false
    }

    // MARK: - Connect

    /// Requests the read-only calendar scope. If a Google session already
    /// exists (e.g. the user signed in with Google), this adds the scope
    /// incrementally; otherwise it starts a Google sign-in carrying the scope.
    /// Calendar access here is independent of Firebase auth, so it also works
    /// for users who signed into Lunifer with email/password or Apple.
    func connect() async {
        guard let presenter = Self.topViewController() else { return }
        do {
            if let user = GIDSignIn.sharedInstance.currentUser {
                _ = try await user.addScopes([Self.scope], presenting: presenter)
            } else {
                _ = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: presenter,
                    hint: nil,
                    additionalScopes: [Self.scope]
                )
            }
            print("✅ Google calendar connected")
        } catch {
            print("❌ Google calendar connect failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Event fetch

    func events(from start: Date, to end: Date) async -> [CalendarEvent] {
        guard let token = await accessToken() else { return [] }

        let rfc3339 = ISO8601DateFormatter()
        var comps = URLComponents(string: Self.eventsURL)!
        comps.queryItems = [
            URLQueryItem(name: "timeMin",      value: rfc3339.string(from: start)),
            URLQueryItem(name: "timeMax",      value: rfc3339.string(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),   // expand recurring events
            URLQueryItem(name: "orderBy",      value: "startTime"),
            URLQueryItem(name: "maxResults",   value: "50")
        ]
        guard let url = comps.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            let decoded = try JSONDecoder().decode(GoogleEventsResponse.self, from: data)
            return decoded.items.compactMap(Self.mapToCalendarEvent)
        } catch {
            print("❌ Google calendar fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Token

    /// Refreshes the Google access token if needed and returns it, or nil
    /// when there's no Google session / calendar scope.
    private func accessToken() async -> String? {
        guard isConnected(), let user = GIDSignIn.sharedInstance.currentUser else { return nil }
        do {
            let refreshed = try await user.refreshTokensIfNeeded()
            return refreshed.accessToken.tokenString
        } catch {
            print("❌ Google token refresh failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Mapping

    private static func mapToCalendarEvent(_ event: GoogleEvent) -> CalendarEvent? {
        let isAllDay = event.start?.date != nil
        guard let start = event.start?.resolvedDate,
              let end = event.end?.resolvedDate ?? event.start?.resolvedDate else { return nil }

        // Declined only when the current user (the attendee flagged `self`)
        // has responseStatus "declined". No attendees → personal event → attending.
        let declined = event.attendees?.contains {
            ($0.selfAttendee ?? false) && ($0.responseStatus ?? "") == "declined"
        } ?? false

        return CalendarEvent(
            id: event.id ?? UUID().uuidString,
            title: event.summary ?? "Untitled",
            startDate: start,
            endDate: end,
            isAllDay: isAllDay,
            calendarTitle: "Google Calendar",
            calendarColor: Color(red: 0.627, green: 0.471, blue: 1.0),
            location: event.location,
            notes: event.description,
            isDeclinedByUser: declined
        )
    }

    // MARK: - Presentation

    private static func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

// MARK: - Google Calendar API models

private struct GoogleEventsResponse: Decodable {
    let items: [GoogleEvent]
}

private struct GoogleEvent: Decodable {
    let id: String?
    let summary: String?
    let location: String?
    let description: String?
    let start: GoogleEventDate?
    let end: GoogleEventDate?
    let attendees: [GoogleAttendee]?
}

private struct GoogleEventDate: Decodable {
    let dateTime: String?   // RFC3339 timestamp for timed events
    let date: String?       // "yyyy-MM-dd" for all-day events

    /// Resolves either the timed `dateTime` or the all-day `date` to a Date.
    var resolvedDate: Date? {
        if let dateTime {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: dateTime) { return d }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: dateTime)
        }
        if let date {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: date)
        }
        return nil
    }
}

private struct GoogleAttendee: Decodable {
    let selfAttendee: Bool?
    let responseStatus: String?

    // Google's JSON key is the reserved word `self`.
    private enum CodingKeys: String, CodingKey {
        case selfAttendee = "self"
        case responseStatus
    }
}
