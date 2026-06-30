import Foundation
import Combine   // Required for @Published property wrapper and ObservableObject
import EventKit
import SwiftUI

// MARK: - CalendarEvent Model

/// A value-type snapshot of a single calendar event.
struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    let calendarColor: Color
    let location: String?
    let notes: String?

    /// True only when the current user has explicitly DECLINED this event's
    /// invitation. Accepted, tentative, and not-yet-answered invites are all
    /// treated as "attending" (isDeclinedByUser == false) so they still drive
    /// the alarm calculation. Personal events with no attendees are never
    /// declined. Used to exclude declined meetings from the alarm baseline.
    let isDeclinedByUser: Bool

    /// Duration of the event in seconds.
    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    /// Duration of the event rounded to whole minutes.
    var durationMinutes: Int { Int(duration / 60) }
}

// MARK: - CalendarAuthorizationStatus

enum CalendarAuthorizationStatus: Equatable {
    case notDetermined
    case authorized
    case denied
}

// MARK: - CalendarProvider

/// Which calendar back-end supplies events, derived from `SurveyAnswers.calendar`.
/// `apple` reads the iOS system calendar via EventKit; `google` / `microsoft`
/// read the provider's web API directly, so they work even when the account is
/// not synced into the iOS system calendar. `none` means the user has no calendar.
enum CalendarProvider {
    case apple, google, microsoft, none

    init(answer: String?) {
        switch answer {
        case "google":  self = .google
        case "outlook": self = .microsoft
        case "none":    self = .none
        default:        self = .apple   // nil or "apple"
        }
    }
}

// MARK: - CalendarEventSource

/// A back-end that can return Lunifer `CalendarEvent`s for a date range.
/// Implemented by `GoogleCalendarService` and `MicrosoftCalendarService`;
/// EventKit is handled inline by `CalendarManager`.
@MainActor
protocol CalendarEventSource {
    func isConnected() -> Bool
    func events(from start: Date, to end: Date) async -> [CalendarEvent]
}

// MARK: - CalendarManager

/// Wraps EventKit to request calendar access and surface events to SwiftUI.
///
/// Usage:
/// ```swift
///@StateObject private var calendarManager = CalendarManager()
/// // …
/// .environmentObject(calendarManager)
/// ```
@MainActor
final class CalendarManager: ObservableObject {

    /// Shared singleton so the alarm engine can query calendar events
    /// without requiring a SwiftUI environment object.
    static let shared = CalendarManager()

    // MARK: Published State

    /// Current system-level authorization state.
    @Published var authorizationStatus: CalendarAuthorizationStatus = .notDetermined

    /// Events occurring today (midnight → midnight).
    @Published var todayEvents: [CalendarEvent] = []

    /// Events occurring in the next 7 days (not including today).
    @Published var upcomingEvents: [CalendarEvent] = []

    /// True while an event fetch is in progress.
    @Published var isLoading: Bool = false

    /// Non-nil if the last fetch or request encountered an error.
    @Published var errorMessage: String? = nil

    // MARK: Private

    private let eventStore = EKEventStore()

    // MARK: Init

    init() {
        refreshAuthorizationStatus()
    }

    // MARK: Authorization

    /// Reads the current system status and updates `authorizationStatus`.
    func refreshAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            authorizationStatus = .authorized
        case .denied, .restricted, .writeOnly:
            authorizationStatus = .denied
        case .notDetermined:
            authorizationStatus = .notDetermined
        @unknown default:
            authorizationStatus = .notDetermined
        }
    }

    /// Requests calendar read access from the user.
    /// Automatically fetches events after a successful grant.
    func requestAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorizationStatus = granted ? .authorized : .denied
            if granted {
                await fetchEvents()
            }
        } catch {
            authorizationStatus = .denied
            errorMessage = "Calendar access failed: \(error.localizedDescription)"
        }
    }

    // MARK: Fetching

    /// Fetches today's and the next 7 days of events from whichever back-end
    /// matches the user's chosen provider (`SurveyAnswers.calendar`):
    ///   • apple     → EventKit (iOS system calendar)
    ///   • google    → Google Calendar API
    ///   • microsoft → Microsoft Graph (Outlook)
    ///   • none      → no events
    /// Reading Google/Outlook over their APIs means events appear even when the
    /// account is NOT synced into the iOS system calendar. Safe to call repeatedly.
    func fetchEvents() async {
        let provider = CalendarProvider(answer: SurveyAnswersStore.shared.loadFromDefaults()?.calendar)

        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        guard let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart),
              let upcomingEnd = cal.date(byAdding: .day, value: 7, to: todayStart) else {
            return
        }

        switch provider {
        case .apple:
            await fetchFromEventKit(todayStart: todayStart, todayEnd: todayEnd, upcomingEnd: upcomingEnd)
        case .google:
            await fetchFromService(GoogleCalendarService.shared, todayEnd: todayEnd, upcomingEnd: upcomingEnd)
        case .microsoft:
            await fetchFromService(MicrosoftCalendarService.shared, todayEnd: todayEnd, upcomingEnd: upcomingEnd)
        case .none:
            todayEvents = []
            upcomingEvents = []
        }
    }

    /// EventKit path (Apple system calendar). No-ops when not authorized.
    private func fetchFromEventKit(todayStart: Date, todayEnd: Date, upcomingEnd: Date) async {
        guard authorizationStatus == .authorized else { return }

        isLoading = true
        errorMessage = nil

        todayEvents = fetchEKEvents(from: todayStart, to: todayEnd)
            .map(mapToCalendarEvent)
            .sorted { $0.startDate < $1.startDate }

        // Upcoming: tomorrow → 7 days from today
        upcomingEvents = fetchEKEvents(from: todayEnd, to: upcomingEnd)
            .map(mapToCalendarEvent)
            .sorted { $0.startDate < $1.startDate }

        isLoading = false
    }

    /// Web-API path (Google / Microsoft). Pulls the full today→+7d window in one
    /// request, then splits it into today vs. upcoming to match the EventKit shape.
    private func fetchFromService(_ source: CalendarEventSource, todayEnd: Date, upcomingEnd: Date) async {
        guard source.isConnected() else {
            // Not connected yet (user hasn't granted calendar access) — clear so
            // downstream logic falls back to historical pattern / 8 AM.
            todayEvents = []
            upcomingEvents = []
            return
        }

        isLoading = true
        errorMessage = nil

        let todayStart = Calendar.current.startOfDay(for: Date())
        let all = await source.events(from: todayStart, to: upcomingEnd)

        todayEvents = all
            .filter { $0.startDate >= todayStart && $0.startDate < todayEnd }
            .sorted { $0.startDate < $1.startDate }
        upcomingEvents = all
            .filter { $0.startDate >= todayEnd && $0.startDate < upcomingEnd }
            .sorted { $0.startDate < $1.startDate }

        isLoading = false
    }

    // MARK: Convenience Accessors

    /// Returns all fetched events for a specific calendar date.
    func events(for date: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return (todayEvents + upcomingEvents)
            .filter { $0.startDate >= dayStart && $0.startDate < dayEnd }
    }

    /// The next event that has not yet started, or nil if none.
    var nextEvent: CalendarEvent? {
        let now = Date()
        return (todayEvents + upcomingEvents)
            .filter { $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    /// The earliest non-all-day event tomorrow, or nil if none.
    /// This is the primary input for Lunifer's calendar-driven alarm calculation.
    var firstEventTomorrow: CalendarEvent? {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())),
              let dayEnd   = cal.date(byAdding: .day, value: 1, to: tomorrow) else { return nil }

        return (todayEvents + upcomingEvents)
            .filter { !$0.isAllDay && !$0.isDeclinedByUser && $0.startDate >= tomorrow && $0.startDate < dayEnd }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    /// The earliest non-all-day, non-declined event today, or nil if none.
    /// Mirrors `firstEventTomorrow`'s filtering so the commute card anchors to
    /// an event the user is actually attending — not a declined meeting or an
    /// all-day entry. Use this (not `todayEvents.first`) wherever "today's first
    /// real event" is needed.
    var firstEventToday: CalendarEvent? {
        todayEvents
            .filter { !$0.isAllDay && !$0.isDeclinedByUser }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    // MARK: Historical Pattern Queries

    /// Returns the average start time (hour, minute) of the earliest non-all-day
    /// calendar event on a given weekday over the past 6 weeks.
    ///
    /// Used as the first fallback when no event exists for tomorrow but the user
    /// has wake days that include tomorrow — e.g. a Friday with no meetings that
    /// still requires an early start based on historical patterns.
    ///
    /// Requires at least 2 matching days to return a result, to avoid a single
    /// anomalous event skewing the average.
    ///
    /// - Parameter weekday: EKWeekday integer (1 = Sunday … 7 = Saturday),
    ///   matching Calendar.current.component(.weekday, from:).
    func typicalFirstEventTime(forWeekday weekday: Int) -> (hour: Int, minute: Int)? {
        guard authorizationStatus == .authorized else { return nil }

        let cal = Calendar.current
        let now = Date()
        guard let sixWeeksAgo = cal.date(byAdding: .weekOfYear, value: -6, to: now),
              let startOfToday = cal.date(bySettingHour: 0, minute: 0, second: 0, of: now),
              let yesterday = cal.date(byAdding: .second, value: -1, to: startOfToday)
        else { return nil }

        // Collect the earliest event start per matching calendar day.
        var earliestPerDay: [String: Date] = [:]

        for event in fetchEKEvents(from: sixWeeksAgo, to: yesterday) {
            guard !event.isAllDay else { continue }
            // Skip meetings the user declined — they shouldn't shape the
            // historical "typical first event" pattern either.
            guard !Self.isDeclinedByCurrentUser(event) else { continue }
            guard cal.component(.weekday, from: event.startDate) == weekday else { continue }

            // Key by calendar date so we group events on the same day together.
            let dayKey = cal.startOfDay(for: event.startDate).description
            if let existing = earliestPerDay[dayKey] {
                if event.startDate < existing { earliestPerDay[dayKey] = event.startDate }
            } else {
                earliestPerDay[dayKey] = event.startDate
            }
        }

        // Need at least 2 data points to produce a meaningful average.
        guard earliestPerDay.count >= 2 else { return nil }

        let totalMinutes = earliestPerDay.values.reduce(0) { sum, date in
            sum + cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        }
        let avgMinutes = totalMinutes / earliestPerDay.count
        return (hour: avgMinutes / 60, minute: avgMinutes % 60)
    }

    // MARK: Private Helpers

    private func fetchEKEvents(from start: Date, to end: Date) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: nil      // nil = search all calendars
        )
        return eventStore.events(matching: predicate)
    }

    private func mapToCalendarEvent(_ event: EKEvent) -> CalendarEvent {
        let color: Color = {
            if let cg = event.calendar.cgColor {
                return Color(cg)
            }
            return Color(red: 0.627, green: 0.471, blue: 1.0) // Lunifer accent fallback
        }()
        return CalendarEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Untitled",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            calendarTitle: event.calendar.title,
            calendarColor: color,
            location: event.location,
            notes: event.notes,
            isDeclinedByUser: Self.isDeclinedByCurrentUser(event)
        )
    }

    /// Returns true only when the current user is an attendee on `event` AND
    /// their participation status is `.declined`. Returns false for personal
    /// events (no attendees) and for any invite the user has accepted, marked
    /// tentative, or not yet responded to — an un-answered invite counts as
    /// "attending" so it still feeds the alarm calculation.
    nonisolated static func isDeclinedByCurrentUser(_ event: EKEvent) -> Bool {
        guard let attendees = event.attendees else { return false }
        for participant in attendees where participant.isCurrentUser {
            return participant.participantStatus == .declined
        }
        return false
    }
}
