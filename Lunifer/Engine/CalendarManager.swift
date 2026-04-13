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

    /// Fetches today's and the next 7 days of events from the system calendar store.
    ///
    /// Safe to call multiple times; no-ops when not authorized.
    func fetchEvents() async {
        guard authorizationStatus == .authorized else { return }

        isLoading = true
        errorMessage = nil

        let cal = Calendar.current
        let now = Date()

        let todayStart = cal.startOfDay(for: now)
        guard let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart),
              let upcomingEnd = cal.date(byAdding: .day, value: 7, to: todayStart) else {
            isLoading = false
            return
        }

        todayEvents = fetchEKEvents(from: todayStart, to: todayEnd)
            .map(mapToCalendarEvent)
            .sorted { $0.startDate < $1.startDate }

        // Upcoming: tomorrow → 7 days from today
        upcomingEvents = fetchEKEvents(from: todayEnd, to: upcomingEnd)
            .map(mapToCalendarEvent)
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
            .filter { !$0.isAllDay && $0.startDate >= tomorrow && $0.startDate < dayEnd }
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
            notes: event.notes
        )
    }
}
