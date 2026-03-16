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
