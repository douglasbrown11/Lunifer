import Foundation
import Combine
import BackgroundTasks
import MapKit
import CoreLocation

// ─────────────────────────────────────────────────────────────
// CommuteManager
// ─────────────────────────────────────────────────────────────
// Owns commute-duration state and drives the leave-reminder
// and delta-alert notification pipeline.
//
// ── Polling strategy ──────────────────────────────────────────
// Two complementary mechanisms are used so polling works both
// in the foreground and in the background:
//
//   Foreground — a 10-minute Timer runs while the app is open.
//     iOS suspends the timer automatically when the app is
//     backgrounded, so it is safe to leave running.
//
//   Background — a BGAppRefreshTask (identifier:
//     "com.lunifer.commuteRefresh") keeps the chain alive when
//     the app is suspended. iOS controls exactly when it fires
//     (typically within 10-30 min of the requested window).
//     The handler reschedules itself before doing work so the
//     chain never breaks.
//
// ── Persisted state ───────────────────────────────────────────
// When iOS relaunches the app to handle a background task, all
// in-memory properties reset to their zero values. Three keys
// are therefore mirrored to UserDefaults so the background
// handler can reconstruct the session correctly:
//
//   commuteArrivalTimestamp       — epoch of the arrival target
//   commutePreviousDurationMinutes — last known duration for delta comparison
//   commutePollingActive          — whether polling should be running at all
//
// ── Delta detection ──────────────────────────────────────────
// On each refresh, the new duration is compared against the
// persisted previousDurationMinutes. A change of ≥5 minutes in
// either direction triggers CommuteNotification.scheduleDeltaAlert
// and updates the persisted baseline.
//
// ── Routing ───────────────────────────────────────────────────
// refreshDuration() calls fetchLiveDuration(), which issues an
// async MKDirections request from stored home → work coordinates.
// Falls back to the survey-entered duration when either location
// is not yet set. The delta detection, notification, and
// persistence plumbing all operate on the returned value.

@MainActor
final class CommuteManager: ObservableObject {

    static let shared = CommuteManager()

    // Background task identifier — must match Info.plist
    nonisolated static let backgroundTaskID = "com.lunifer.commuteRefresh"

    // ── Published state ───────────────────────────────────────

    @Published var currentDurationMinutes: Int = 0
    @Published var lastFetched: Date?          = nil

    // ── Persisted state keys (UserDefaults) ───────────────────

    private let arrivalKey       = AppPreferencesStore.Keys.commuteArrivalTimestamp
    private let prevDurationKey  = AppPreferencesStore.Keys.commutePreviousDurationMinutes
    private let pollingActiveKey = AppPreferencesStore.Keys.commutePollingActive

    private var arrivalDate: Date {
        get {
            let ts = UserDefaults.standard.double(forKey: arrivalKey)
            return ts > 0 ? Date(timeIntervalSince1970: ts) : Date()
        }
        set { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: arrivalKey) }
    }

    private var previousDurationMinutes: Int {
        get { UserDefaults.standard.integer(forKey: prevDurationKey) }
        set { UserDefaults.standard.set(newValue, forKey: prevDurationKey) }
    }

    private var pollingActive: Bool {
        get { UserDefaults.standard.bool(forKey: pollingActiveKey) }
        set { UserDefaults.standard.set(newValue, forKey: pollingActiveKey) }
    }

    // ── Foreground timer ──────────────────────────────────────

    private var pollingTimer: Timer? = nil

    // ── Background task registration ──────────────────────────

    /// Call once from LuniferApp.init() before the app finishes launching.
    nonisolated static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskID,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await CommuteManager.shared.handleBackgroundTask(refreshTask)
            }
        }
    }

    // ── Public API ────────────────────────────────────────────

    /// Begins commute monitoring for a given arrival deadline.
    /// Safe to call multiple times — stops any existing polling first.
    func startPolling(answers: SurveyAnswers, arrivalDate: Date) {
        let duration = Self.surveyDuration(from: answers)

        // Persist state so the background task handler can read it
        // even if the app has been suspended and relaunched by iOS
        self.arrivalDate            = arrivalDate
        self.previousDurationMinutes = duration
        self.pollingActive          = true

        currentDurationMinutes = duration
        lastFetched            = Date()

        // Schedule the initial leave reminder
        let leaveTime = arrivalDate.addingTimeInterval(-Double(duration) * 60)
        CommuteNotification.shared.scheduleLeaveReminder(leaveTime: leaveTime)

        // Foreground: 10-min Timer (suspends automatically when app backgrounds)
        stopTimer()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let answers = SurveyAnswersStore.shared.loadFromDefaults() {
                    await self.refreshDuration(answers: answers)
                }
            }
        }

        // Background: BGAppRefreshTask for when app is suspended
        scheduleBackgroundRefresh()

        print("🚗 CommuteManager polling started — \(duration) min, arrive by \(arrivalDate)")
    }

    /// Tears down both the foreground timer and the background task chain,
    /// and marks polling as inactive in UserDefaults.
    func stopPolling() {
        stopTimer()
        pollingActive = false
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskID)
        print("🚗 CommuteManager polling stopped")
    }

    /// Returns the leave-by time for a given arrival deadline and duration.
    func leaveTime(forArrival arrival: Date, durationMinutes: Int) -> Date {
        arrival.addingTimeInterval(-Double(durationMinutes) * 60)
    }

    // ── Internal — foreground ─────────────────────────────────

    private func stopTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    /// Checks for a duration change and fires a delta alert if the shift is ≥5 min.
    /// Also stops polling automatically once the leave time has passed.
    ///
    /// Uses a live MKDirections fetch when both home and work coordinates are stored.
    /// Falls back to the survey-entered duration if either location is missing.
    private func refreshDuration(answers: SurveyAnswers) async {
        // Auto-stop once the user should have left
        let leave = arrivalDate.addingTimeInterval(-Double(currentDurationMinutes) * 60)
        guard Date() < leave else {
            stopPolling()
            return
        }

        let newDuration = await Self.fetchLiveDuration(answers: answers)

        let delta = newDuration - previousDurationMinutes

        if abs(delta) >= 5 {
            let newLeave = arrivalDate.addingTimeInterval(-Double(newDuration) * 60)
            CommuteNotification.shared.scheduleDeltaAlert(
                newLeaveTime: newLeave,
                didIncrease:  delta > 0
            )
            previousDurationMinutes = newDuration  // persists to UserDefaults
            print("🚗 Commute delta: \(delta > 0 ? "+" : "")\(delta) min — new leave by \(newLeave)")
        }

        currentDurationMinutes = newDuration
        lastFetched            = Date()
    }

    /// Fetches a live commute duration via MKDirections using stored home → work
    /// coordinates. Returns the survey-entered fallback if either location is
    /// missing or if the routing request fails.
    static func fetchLiveDuration(answers: SurveyAnswers) async -> Int {
        let defaults = UserDefaults.standard
        let homeSet  = defaults.bool(forKey: AppPreferencesStore.Keys.homeLocationSet)
        let workSet  = defaults.bool(forKey: AppPreferencesStore.Keys.workLocationSet)

        guard homeSet && workSet else {
            return surveyDuration(from: answers)
        }

        let homeLat = defaults.double(forKey: AppPreferencesStore.Keys.homeLatitude)
        let homeLon = defaults.double(forKey: AppPreferencesStore.Keys.homeLongitude)
        let workLat = defaults.double(forKey: AppPreferencesStore.Keys.workLatitude)
        let workLon = defaults.double(forKey: AppPreferencesStore.Keys.workLongitude)

        let origin      = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: homeLat, longitude: homeLon)))
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: workLat, longitude: workLon)))

        let request = MKDirections.Request()
        request.source           = origin
        request.destination      = destination
        request.transportType    = mkTransportType(for: answers.commuteMode)
        request.departureDate    = Date()

        do {
            let response = try await MKDirections(request: request).calculate()
            if let route = response.routes.first {
                let minutes = Int(route.expectedTravelTime / 60)
                print("🚗 Live commute: \(minutes) min via \(answers.commuteMode)")
                return minutes
            }
        } catch {
            print("🚗 MKDirections error: \(error.localizedDescription)")
        }

        return surveyDuration(from: answers)
    }

    /// Maps a Lunifer commute mode string to the closest MKDirectionsTransportType.
    /// Note: MKDirections does not have a dedicated cycling type; "bike" falls back
    /// to walking, which is the closest available approximation.
    private static func mkTransportType(for commuteMode: String) -> MKDirectionsTransportType {
        switch commuteMode {
        case "transit": return .transit
        case "walk":    return .walking
        case "bike":    return .walking   // no cycling type in MKDirections
        default:        return .automobile
        }
    }

    // ── Internal — background ─────────────────────────────────

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskID)
        // Request a refresh in ~10 minutes; iOS may delay based on usage patterns
        request.earliestBeginDate = Date().addingTimeInterval(10 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Commute background refresh scheduled")
        } catch {
            print("⚠️ Failed to schedule commute background refresh: \(error.localizedDescription)")
        }
    }

    /// Called by iOS when the background task fires. Reads all session state
    /// from UserDefaults because in-memory properties may have been wiped if
    /// the app was suspended and relaunched by the OS.
    private func handleBackgroundTask(_ task: BGAppRefreshTask) async {
        // Reschedule first so the chain continues even if we exit early
        scheduleBackgroundRefresh()

        task.expirationHandler = {
            print("⚠️ Commute background refresh expired by iOS")
        }

        // Nothing to do if polling was cancelled before this task fired
        guard pollingActive else {
            task.setTaskCompleted(success: true)
            return
        }

        // Auto-stop if leave time has already passed
        let leave = arrivalDate.addingTimeInterval(-Double(previousDurationMinutes) * 60)
        guard Date() < leave else {
            stopPolling()
            task.setTaskCompleted(success: true)
            return
        }

        // Refresh using the latest survey answers from UserDefaults
        if let answers = SurveyAnswersStore.shared.loadFromDefaults() {
            await refreshDuration(answers: answers)
        }

        task.setTaskCompleted(success: true)
    }

    // ── Helpers ───────────────────────────────────────────────

    /// Extracts the commute duration in minutes from survey answers.
    /// Returns 0 for non-commuter lifestyles.
    static func surveyDuration(from answers: SurveyAnswers) -> Int {
        guard answers.lifestyle == "student" || answers.lifestyle == "commuter" else { return 0 }
        return answers.commute.auto
            ? 30
            : answers.commute.hours * 60 + answers.commute.minutes
    }
}
