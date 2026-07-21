import Foundation
import UserNotifications

// ─────────────────────────────────────────────────────────────
// CalendarNudgeNotification
// ─────────────────────────────────────────────────────────────
// Encourages the user to keep their calendar populated so Lunifer
// can time the alarm around their real schedule.
//
// Fires when a calendar event has NOT driven the alarm calculation
// (Step 1 of LuniferAlarm.resolveBaselineAlarmDate) in over 7 of the
// user's wake days — i.e. the connected calendar has had no timed,
// attended event on every wake day for more than a week, so the alarm
// has been falling back to historical / sleep-onset / 8 AM instead.
//
// ── SCOPE ─────────────────────────────────────────────────────
//  • Only for users whose calendar is actually connected: Apple with
//    granted EventKit access, or Google / Outlook signed in. Users who
//    chose "None" or never granted access are never nudged — the fix
//    for them isn't "add events."
//  • Respects the master allNotificationsEnabled toggle. There is no
//    separate visible toggle for this reminder (like the hidden rest-day
//    reminder); the master switch is the only control.
//  • Delivered at 7 PM in the user's LOCAL time zone (scheduled on-device
//    with a calendar trigger, so hour 19 means 7 PM wherever they are —
//    there is no shared absolute fire time across time zones).
//  • Sent at most ONCE per empty streak. If the user ignores it and never
//    touches their calendar, they are nudged exactly once — never
//    repeatedly. The streak (and the ability to nudge again) resets only
//    when a calendar event drives the alarm once more, i.e. the user
//    re-engages with their calendar and later drifts empty again.
//
// ── TRACKING ──────────────────────────────────────────────────
//  recordCalendarEventUsed() is called from resolveBaselineAlarmDate
//  whenever a real event drives the alarm; it stamps "now" so the
//  wake-day counter resets. checkAndNudgeIfNeeded(answers:) counts the
//  user's wake days elapsed since that stamp and fires when it exceeds 7.
//
//  On a brand-new install the "last event driven" stamp is seeded to
//  now the first time the check runs with no event, so a fresh user is
//  never nudged before a full week of empty wake days has actually passed.
//
//  Keys are self-contained in this file (same pattern as
//  MorningRoutineEstimator / SleepTrackingStore) and cleared on
//  sign-out via clearStoredData() in AccountDataManager.

final class CalendarNudgeNotification {

    static let shared = CalendarNudgeNotification()
    private init() {}

    private let notificationID = "lunifer.calendar.nudge"

    // UserDefaults keys (not centralised in AppPreferencesStore.Keys)
    private static let lastEventDrivenKey = "lunifer_calendar_last_event_driven"
    private static let sentThisStreakKey  = "lunifer_calendar_nudge_sent_streak"

    /// Number of the user's wake days that must elapse with no calendar-driven
    /// alarm before the nudge fires.
    private let wakeDayThreshold = 7

    // ── Signal intake ─────────────────────────────────────────

    /// Call whenever a real calendar event drives the alarm calculation
    /// (Step 1 of resolveBaselineAlarmDate). Resets the "days since a calendar
    /// event was used" counter by stamping now.
    func recordCalendarEventUsed() {
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970, forKey: Self.lastEventDrivenKey)
        // A calendar event is driving the alarm again, so this empty streak is
        // over. Clear the "already nudged this streak" flag so a *future* empty
        // streak can nudge once more, and cancel any nudge still pending from this
        // streak (they engaged before it fired — no need to send it).
        if defaults.bool(forKey: Self.sentThisStreakKey) {
            defaults.set(false, forKey: Self.sentThisStreakKey)
            cancel()
        }
    }

    // ── Check + fire ──────────────────────────────────────────

    /// Sends the nudge if a calendar event hasn't driven the alarm in over
    /// `wakeDayThreshold` wake days, the user's calendar is connected, the master
    /// notifications toggle is on, and no nudge has been sent in the last week.
    /// Call on dashboard load (after resolveAlarmDate has run).
    @MainActor
    func checkAndNudgeIfNeeded(answers: SurveyAnswers) async {
        // Respect the master toggle (a missing key means enabled).
        guard UserDefaults.standard.object(forKey: "allNotificationsEnabled") as? Bool != false else { return }

        // Only nudge users who actually have a calendar connected.
        guard calendarIsConnected(answers: answers) else { return }

        let defaults = UserDefaults.standard

        // Seed on first run so a brand-new user isn't nudged immediately —
        // the wake-day counter starts from the first time the calendar was
        // empty rather than from the epoch.
        let lastTS = defaults.double(forKey: Self.lastEventDrivenKey)
        guard lastTS > 0 else {
            defaults.set(Date().timeIntervalSince1970, forKey: Self.lastEventDrivenKey)
            return
        }
        let lastEventDriven = Date(timeIntervalSince1970: lastTS)

        // Count the user's wake days elapsed since a calendar event last drove the alarm.
        let wakeDaysElapsed = Self.wakeDaysBetween(
            start: lastEventDriven,
            end: Date(),
            wakeDays: answers.wakeDays
        )
        guard wakeDaysElapsed > wakeDayThreshold else { return }

        // Only nudge ONCE per empty streak. The flag is cleared in
        // recordCalendarEventUsed() when a calendar event drives the alarm again,
        // so a user who ignores the nudge and never touches their calendar is
        // nudged exactly once — not repeatedly — while a user who re-engages and
        // later drifts empty again can receive a fresh nudge.
        guard !defaults.bool(forKey: Self.sentThisStreakKey) else { return }

        // Permission check.
        let center   = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else {
            print("⏭️ Calendar nudge skipped — notifications not authorised")
            return
        }

        // ── Build + send ──────────────────────────────────────
        let content = UNMutableNotificationContent()
        content.title             = "Give Lunifer a look at your week"
        content.body              = "Lunifer hasn't seen an event on your calendar in a while. Add your meetings and classes, and it'll wake you right on time for them."
        content.sound             = .default
        content.interruptionLevel = .passive

        // Deliver at 7:00 PM in the user's LOCAL time zone. Because the
        // notification is scheduled on-device with a calendar trigger,
        // Calendar.current (the device time zone) makes hour 19 mean 7 PM
        // wherever the user is — a New York user gets it at 7 PM ET, a London
        // user at 7 PM GMT, with no shared absolute fire time. Schedule today if
        // 7 PM hasn't passed yet, otherwise tomorrow.
        let cal = Calendar.current
        let sevenPMToday = cal.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()
        let fireDate = Date() < sevenPMToday
            ? sevenPMToday
            : (cal.date(byAdding: .day, value: 1, to: sevenPMToday) ?? sevenPMToday)
        let fireComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: fireComps, repeats: false)

        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        let request = UNNotificationRequest(
            identifier: notificationID,
            content:    content,
            trigger:    trigger
        )
        do {
            try await center.add(request)
            // Mark this empty streak as nudged so we don't send again until a
            // calendar event drives the alarm at least once more.
            defaults.set(true, forKey: Self.sentThisStreakKey)
            print("📅 Calendar nudge scheduled for \(fireDate) — \(wakeDaysElapsed) wake days without a calendar-driven alarm")
        } catch {
            print("❌ Calendar nudge failed: \(error.localizedDescription)")
        }
    }

    /// Cancels any pending nudge.
    func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID])
    }

    // ── Helpers ───────────────────────────────────────────────

    /// True only when the user's chosen calendar provider is actually connected.
    /// Apple → EventKit access granted; Google / Outlook → signed in. "None"
    /// or an unauthorised provider returns false so those users are never nudged.
    @MainActor
    private func calendarIsConnected(answers: SurveyAnswers) -> Bool {
        switch CalendarProvider(answer: answers.calendar) {
        case .apple:     return CalendarManager.shared.authorizationStatus == .authorized
        case .google:    return GoogleCalendarService.shared.isConnected()
        case .microsoft: return MicrosoftCalendarService.shared.isConnected()
        case .none:      return false
        }
    }

    /// Counts how many of the user's wake days fall strictly after `start`'s
    /// calendar day, up to and including `end`'s calendar day.
    static func wakeDaysBetween(start: Date, end: Date, wakeDays: [String]) -> Int {
        let cal = Calendar.current
        let ids = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        var count = 0
        var day = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end)
        while day < endDay {
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            let id = ids[cal.component(.weekday, from: day) - 1]
            if wakeDays.contains(id) { count += 1 }
            if count > 1000 { break }   // safety guard against runaway loops
        }
        return count
    }

    /// Nonisolated wipe of persisted keys for sign-out / delete-account cleanup.
    nonisolated static func clearStoredData() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: lastEventDrivenKey)
        defaults.removeObject(forKey: sentThisStreakKey)
    }
}
