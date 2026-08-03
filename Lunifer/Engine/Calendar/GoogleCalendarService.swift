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
//   • connect() — obtain the read-only event + calendar-list scopes (incremental
//     consent on top of whatever Google session already exists, or a
//     fresh Google sign-in if there isn't one).
//   • events(from:to:) — fetch the user's visible calendars and merge their
//     events for a date range.
//
// Declined / all-day events are flagged on the returned CalendarEvent so
// the alarm baseline can filter them, matching the EventKit path.
//
// Setup required (outside this file):
//   • The Google Cloud OAuth consent screen must list the
//     `calendar.events.readonly` and `calendar.calendarlist.readonly` scopes.
//     No client secret is needed on device.

@MainActor
final class GoogleCalendarService: NSObject, ObservableObject, CalendarEventSource {

    static let shared = GoogleCalendarService()

    static let eventScope = "https://www.googleapis.com/auth/calendar.events.readonly"
    static let calendarListScope = "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
    static let scopes = [eventScope, calendarListScope]

    private static let calendarListURL = "https://www.googleapis.com/calendar/v3/users/me/calendarList"
    private static let eventsBaseURL = "https://www.googleapis.com/calendar/v3/calendars"

    private override init() { super.init() }

    // MARK: - CalendarEventSource

    /// Connected when the current Google session has granted both scopes required
    /// to discover visible calendars and read their events.
    func isConnected() -> Bool {
        guard let grantedScopes = GIDSignIn.sharedInstance.currentUser?.grantedScopes else {
            return false
        }
        return Self.scopes.allSatisfy(grantedScopes.contains)
    }

    // MARK: - Connect

    /// Requests the least-privilege event and calendar-list scopes. If a Google
    /// session already exists (e.g. the user signed in with Google), this adds them
    /// incrementally; otherwise it starts a Google sign-in carrying the scope.
    /// Calendar access here is independent of Firebase auth, so it also works
    /// for users who signed into Lunifer with email/password or Apple.
    func connect() async {
        guard let presenter = Self.topViewController() else { return }
        do {
            if let user = GIDSignIn.sharedInstance.currentUser {
                let grantedScopes = user.grantedScopes ?? []
                let missingScopes = Self.scopes.filter { !grantedScopes.contains($0) }
                if !missingScopes.isEmpty {
                    _ = try await user.addScopes(missingScopes, presenting: presenter)
                }
            } else {
                _ = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: presenter,
                    hint: nil,
                    additionalScopes: Self.scopes
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

        let calendars = await fetchVisibleCalendars(accessToken: token)
        var eventsByStableID: [String: CalendarEvent] = [:]

        for calendar in calendars {
            let events = await fetchEvents(
                calendarID: calendar.id,
                calendarTitle: calendar.summary,
                from: start,
                to: end,
                accessToken: token
            )
            for event in events {
                eventsByStableID[event.stableID] = event.calendarEvent
            }
        }

        return eventsByStableID.values.sorted { $0.startDate < $1.startDate }
    }

    /// Returns calendars the user currently has selected in Google Calendar,
    /// plus the primary calendar even if its selected flag is absent. Hidden or
    /// unchecked calendars are excluded so Lunifer mirrors the schedule the user
    /// normally sees. Falls back to primary if the list request fails.
    private func fetchVisibleCalendars(accessToken: String) async -> [GoogleCalendarListEntry] {
        var calendars: [GoogleCalendarListEntry] = []
        var pageToken: String?

        repeat {
            var comps = URLComponents(string: Self.calendarListURL)!
            comps.queryItems = [URLQueryItem(name: "maxResults", value: "250")]
            if let pageToken {
                comps.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            guard let url = comps.url else { break }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode) else { break }
                let decoded = try JSONDecoder().decode(GoogleCalendarListResponse.self, from: data)
                calendars.append(contentsOf: decoded.items)
                pageToken = decoded.nextPageToken
            } catch {
                print("❌ Google calendar-list fetch failed: \(error.localizedDescription)")
                break
            }
        } while pageToken != nil

        let visible = calendars.filter { entry in
            entry.primary == true || (entry.selected == true && entry.hidden != true)
        }
        if !visible.isEmpty { return visible }
        return [GoogleCalendarListEntry(
            id: "primary",
            summary: "Google Calendar",
            primary: true,
            selected: true,
            hidden: false
        )]
    }

    private func fetchEvents(
        calendarID: String,
        calendarTitle: String,
        from start: Date,
        to end: Date,
        accessToken: String
    ) async -> [(stableID: String, calendarEvent: CalendarEvent)] {
        let rfc3339 = ISO8601DateFormatter()
        let encodedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? calendarID
        var results: [(stableID: String, calendarEvent: CalendarEvent)] = []
        var pageToken: String?

        repeat {
            var comps = URLComponents(string: "\(Self.eventsBaseURL)/\(encodedCalendarID)/events")!
            comps.queryItems = [
                URLQueryItem(name: "timeMin", value: rfc3339.string(from: start)),
                URLQueryItem(name: "timeMax", value: rfc3339.string(from: end)),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "2500")
            ]
            if let pageToken {
                comps.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            guard let url = comps.url else { break }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode) else { break }
                let decoded = try JSONDecoder().decode(GoogleEventsResponse.self, from: data)
                results.append(contentsOf: decoded.items.compactMap { event in
                    guard let mapped = Self.mapToCalendarEvent(event, calendarTitle: calendarTitle) else {
                        return nil
                    }
                    return (event.iCalUID ?? "\(calendarID):\(event.id ?? mapped.id)", mapped)
                })
                pageToken = decoded.nextPageToken
            } catch {
                print("❌ Google calendar fetch failed for \(calendarTitle): \(error.localizedDescription)")
                break
            }
        } while pageToken != nil

        return results
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

    private static func mapToCalendarEvent(
        _ event: GoogleEvent,
        calendarTitle: String
    ) -> CalendarEvent? {
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
            calendarTitle: calendarTitle,
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
    let nextPageToken: String?
}

private struct GoogleCalendarListResponse: Decodable {
    let items: [GoogleCalendarListEntry]
    let nextPageToken: String?
}

private struct GoogleCalendarListEntry: Decodable {
    let id: String
    let summary: String
    let primary: Bool?
    let selected: Bool?
    let hidden: Bool?
}

private struct GoogleEvent: Decodable {
    let id: String?
    let iCalUID: String?
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
