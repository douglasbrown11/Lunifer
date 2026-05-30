import SwiftUI
import FirebaseAuth
import AVFoundation
import Combine
import CoreMotion
import UIKit

// ── MARK: Added Alarm Model ───────────────────────────────────

struct AddedAlarm: Codable, Identifiable {
    var id: UUID
    var timestamp: Double
    var label: String
    var sound: String
    var snoozeMinutes: Int
    /// Empty array = one-shot; non-empty = repeating on those weekday IDs ("mon"…"sun").
    var repeatDays: [String]

    // Explicit memberwise init — repeatDays defaults to [] (one-shot).
    init(id: UUID, timestamp: Double, label: String, sound: String,
         snoozeMinutes: Int, repeatDays: [String] = []) {
        self.id            = id
        self.timestamp     = timestamp
        self.label         = label
        self.sound         = sound
        self.snoozeMinutes = snoozeMinutes
        self.repeatDays    = repeatDays
    }

    // Backward-compatible decoder — existing stored JSON has no repeatDays key.
    init(from decoder: Decoder) throws {
        let c          = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self,   forKey: .id)
        timestamp      = try c.decode(Double.self, forKey: .timestamp)
        label          = try c.decode(String.self, forKey: .label)
        sound          = try c.decode(String.self, forKey: .sound)
        snoozeMinutes  = try c.decode(Int.self,    forKey: .snoozeMinutes)
        repeatDays     = (try? c.decode([String].self, forKey: .repeatDays)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, label, sound, snoozeMinutes, repeatDays
    }

    var date: Date { Date(timeIntervalSince1970: timestamp) }

    var displayTime: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f.string(from: date)
    }

    var displayPeriod: String {
        let f = DateFormatter()
        f.dateFormat = "a"
        return f.string(from: date)
    }

    /// Human-readable repeat summary, or nil when this is a one-shot alarm.
    var displayRepeatDays: String? {
        guard !repeatDays.isEmpty else { return nil }
        if repeatDays.count == 7 { return "Every day" }
        let order  = ["mon","tue","wed","thu","fri","sat","sun"]
        let labels = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
        return order.enumerated()
            .filter { repeatDays.contains($0.element) }
            .map    { labels[$0.offset] }
            .joined(separator: ", ")
    }
}

private struct BaselineAlarmResolution {
    let alarmDate: Date
    let routineMinutes: Int
    let commuteMinutes: Int
    let firstEvent: CalendarEvent?
}

// ── MARK: Dashboard ──────────────────────────────────────────


struct LuniferMain: View {
    @Binding var answers: SurveyAnswers
    @State private var showSettings = false
    @State private var showSound = false
    @State private var currentPage: Int = 1
    @State private var alarmExpanded = false
    @State private var overrideTime = Date()
    @AppStorage("overrideActive") private var overrideActive: Bool = false
    @AppStorage("overrideTimestamp") private var overrideTimestamp: Double = 0
    @AppStorage("luniferEnabled") private var luniferEnabled: Bool = true
    @AppStorage("selectedAlarmSound") private var selectedAlarmSound: String = "DeafultAlarm.wav"
    @AppStorage("mainAlarmSnoozeMinutes") private var mainAlarmSnoozeMinutes: Int = 5
    /// Ticks every minute so rest-period checks re-evaluate automatically,
    /// including the midnight transition back to the alarm view.
    @State private var ticker = Date()

    // ── Added alarm state ─────────────────────────────────────
    @State private var showAddAlarmSheet    = false
    @State private var addAlarmTapped       = false
    @State private var addedAlarmPickerTime = Date()
    @State private var addedAlarms: [AddedAlarm] = []
    @State private var showMotionDeniedAlert = false
    @State private var showAlarmDeniedAlert = false
    @State private var showDebug = false

    // ── Edit-added-alarm state ────────────────────────────────
    // Tapping an added alarm card opens EditAddedAlarmSheet. The sheet
    // mirrors the three controls in the calculated-alarm dropdown:
    // time picker, sound, snooze minutes. The values are seeded from
    // the row before the sheet appears and committed back via saveEdit().
    @State private var showEditAlarmSheet   = false
    @State private var editingAlarmID: UUID? = nil
    @State private var editPickerTime: Date = Date()
    @State private var editSound: String = "DeafultAlarm.wav"
    @State private var editSnoozeMinutes: Int = 5
    @State private var editRepeatDays: [String] = []

    private var isRunningPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private func loadAddedAlarms() {
        guard let data = UserDefaults.standard.data(forKey: "addedAlarms"),
              let decoded = try? JSONDecoder().decode([AddedAlarm].self, from: data)
        else { return }
        addedAlarms = decoded
    }

    private func saveAddedAlarms() {
        if let data = try? JSONEncoder().encode(addedAlarms) {
            UserDefaults.standard.set(data, forKey: "addedAlarms")
        }
    }

    // ── Edit helpers ──────────────────────────────────────────

    /// Seeds the edit-sheet state from the tapped added alarm and presents
    /// the sheet. The label is preserved as-is (the calculated alarm has no
    /// label, so the edit menu intentionally exposes only time/sound/snooze).
    private func startEditingAddedAlarm(_ alarm: AddedAlarm) {
        editingAlarmID    = alarm.id
        editPickerTime    = alarm.date
        editSound         = alarm.sound
        editSnoozeMinutes = alarm.snoozeMinutes
        editRepeatDays    = alarm.repeatDays
        showEditAlarmSheet = true
    }

    /// Persists the edit-sheet values back to the added alarm and re-schedules
    /// it through AlarmKit. scheduleAddedAlarm() is keyed on the logical UUID
    /// so it cancels the previous AlarmKit registration for this row before
    /// scheduling the new one.
    private func commitEditingAddedAlarm() {
        guard let id = editingAlarmID,
              let index = addedAlarms.firstIndex(where: { $0.id == id }) else {
            showEditAlarmSheet = false
            editingAlarmID = nil
            return
        }
        let existing = addedAlarms[index]
        let updated = AddedAlarm(
            id: id,
            timestamp: editPickerTime.timeIntervalSince1970,
            label: existing.label,
            sound: editSound,
            snoozeMinutes: editSnoozeMinutes,
            repeatDays: editRepeatDays
        )
        addedAlarms[index] = updated
        saveAddedAlarms()
        Task { await LuniferAlarm.shared.scheduleAddedAlarm(for: updated.date, alarmID: id, snoozeMinutes: updated.snoozeMinutes) }
        showEditAlarmSheet = false
        editingAlarmID = nil
    }

    /// Removes the alarm from the dashboard list and tears down its AlarmKit
    /// registration. Triggered by the swipe-revealed Delete button.
    private func deleteAddedAlarm(id: UUID) {
        withAnimation(.easeInOut(duration: 0.25)) {
            addedAlarms.removeAll { $0.id == id }
        }
        saveAddedAlarms()
        Task { await LuniferAlarm.shared.cancelAddedAlarm(id: id) }
    }

    /// Finds the next calendar date (after `now`) on which one of the
    /// supplied weekday IDs ("mon"…"sun") falls, using the hour and minute
    /// from `timeOf`. Returns nil if no match is found within 8 days.
    private func nextOccurrence(after now: Date, repeatDays: [String], timeOf: Date) -> Date? {
        let cal = Calendar.current
        let hour   = cal.component(.hour,   from: timeOf)
        let minute = cal.component(.minute, from: timeOf)
        let idForWeekday: [Int: String] = [1:"sun",2:"mon",3:"tue",4:"wed",5:"thu",6:"fri",7:"sat"]
        for offset in 1...8 {
            guard let day = cal.date(byAdding: .day, value: offset,
                                     to: cal.startOfDay(for: now)) else { continue }
            let wdStr = idForWeekday[cal.component(.weekday, from: day)] ?? ""
            guard repeatDays.contains(wdStr) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour; comps.minute = minute; comps.second = 0
            if let proposed = cal.date(from: comps), proposed > now { return proposed }
        }
        return nil
    }

    // ── Resolved alarm date ───────────────────────────────────
    // Single source of truth for tomorrow's Lunifer alarm time.
    // Initialised synchronously to an 8 AM default, then replaced
    // in .task with the result of the 4-step fallback chain:
    //   1. First calendar event tomorrow
    //   2. Historical average first-event time for this weekday
    //   3. Historical average wake time for this weekday
    //   4. 8:00 AM hard fallback
    @State private var resolvedAlarmDate: Date = {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 8; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }()

    /// The Lunifer-calculated alarm date (no manual override applied).
    /// All downstream logic that needs a raw schedule reference uses this.
    private var calculatedAlarmDate: Date { resolvedAlarmDate }

    private var wakeUpTime: String {
        let f = DateFormatter(); f.dateFormat = "h:mm"
        return f.string(from: overrideActive ? overrideTime : resolvedAlarmDate)
    }

    private var wakeUpPeriod: String {
        let f = DateFormatter(); f.dateFormat = "a"
        return f.string(from: overrideActive ? overrideTime : resolvedAlarmDate)
    }

    // ── Alarm date resolution helpers ─────────────────────────

    /// Returns the routine + commute buffer in seconds for synchronous callers.
    ///
    /// When commute auto-mode is on, reads the cached live duration from
    /// CommuteManager (populated by resolveAlarmDate() earlier in the session).
    /// Falls back to 30 minutes on cold start before any live fetch has run.
    private func bufferSeconds() -> TimeInterval {
        let routine = answers.routine.auto
            ? 60
            : answers.routine.hours * 60 + answers.routine.minutes
        let commute: Int = (answers.lifestyle == "student" || answers.lifestyle == "commuter")
            ? (answers.commute.auto
                ? (CommuteManager.shared.currentDurationMinutes > 0
                    ? CommuteManager.shared.currentDurationMinutes
                    : 30)
                : answers.commute.hours * 60 + answers.commute.minutes)
            : 0
        return Double(routine + commute) * 60
    }

    /// Builds a Date for today using the supplied hour and minute.
    private func todayAt(hour: Int, minute: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    /// Builds a Date for tomorrow using the supplied hour and minute.
    /// Used by resolveAlarmDate() so fallback steps land on the correct calendar date
    /// rather than today (which would already be in the past by evening).
    private func tomorrowAt(hour: Int, minute: Int) -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return cal.date(from: comps) ?? Date()
    }

    /// Resolves the best alarm date for tomorrow. The deterministic fallback
    /// chain creates the baseline; the adaptive bandit then chooses a bounded
    /// one-minute offset and clamps it inside the safety window.
    @MainActor
    private func resolveAlarmDate() async -> Date {
        let baseline = await resolveBaselineAlarmDate()
        let context = AlarmContextBuilder.build(
            answers: answers,
            baselineAlarm: baseline.alarmDate,
            routineMinutes: baseline.routineMinutes,
            commuteMinutes: baseline.commuteMinutes,
            firstEvent: baseline.firstEvent
        )

        let oneHour: TimeInterval = 60 * 60
        let latestAllowedAlarm = baseline.firstEvent.map {
            $0.startDate.addingTimeInterval(-Double(baseline.routineMinutes + baseline.commuteMinutes) * 60)
        } ?? baseline.alarmDate.addingTimeInterval(oneHour)

        let safetyWindow = AdaptiveAlarmSafetyWindow(
            earliestAllowedAlarm: baseline.alarmDate.addingTimeInterval(-oneHour),
            latestAllowedAlarm: max(
                baseline.alarmDate.addingTimeInterval(-oneHour),
                latestAllowedAlarm
            )
        )

        let decision = AlarmOffsetBandit.chooseDecision(
            baselineAlarm: baseline.alarmDate,
            context: context,
            safetyWindow: safetyWindow,
            outcomes: AdaptiveAlarmStore.shared.recentOutcomes()
        )
        AdaptiveAlarmStore.shared.savePendingDecision(decision)

        return decision.finalAlarm
    }

    /// Resolves the deterministic baseline alarm for tomorrow using a 4-step
    /// fallback chain.
    /// Asynchronous because steps 1-2 may require a calendar fetch and, when
    /// commute auto-mode is on, a live MKDirections fetch for accurate buffer math.
    @MainActor
    private func resolveBaselineAlarmDate() async -> BaselineAlarmResolution {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let tomorrowWeekday = cal.component(.weekday, from: tomorrow)

        // Compute the wake-up buffer (routine + commute) asynchronously so that
        // auto-commute users get a live MKDirections duration rather than the
        // 30-minute placeholder that bufferSeconds() returns pre-fetch.
        let routineMinutes = answers.routine.auto
            ? 60
            : answers.routine.hours * 60 + answers.routine.minutes
        let commuteMinutes: Int
        if answers.lifestyle == "student" || answers.lifestyle == "commuter" {
            if answers.commute.auto {
                let live = await CommuteManager.fetchLiveDuration(answers: answers)
                // Cache in the shared manager so bufferSeconds() (and the commute
                // card) can read it synchronously for the rest of this session.
                CommuteManager.shared.currentDurationMinutes = live
                commuteMinutes = live
            } else {
                commuteMinutes = answers.commute.hours * 60 + answers.commute.minutes
            }
        } else {
            commuteMinutes = 0
        }
        let buffer = Double(routineMinutes + commuteMinutes) * 60

        // Step 1: Live calendar event tomorrow
        await CalendarManager.shared.fetchEvents()
        if let event = CalendarManager.shared.firstEventTomorrow {
            return BaselineAlarmResolution(
                alarmDate: event.startDate.addingTimeInterval(-buffer),
                routineMinutes: routineMinutes,
                commuteMinutes: commuteMinutes,
                firstEvent: event
            )
        }

        // Step 2: Historical average first-event time for this weekday
        if let typical = CalendarManager.shared.typicalFirstEventTime(forWeekday: tomorrowWeekday) {
            let alarm = tomorrowAt(hour: typical.hour, minute: typical.minute)
                .addingTimeInterval(-buffer)
            return BaselineAlarmResolution(
                alarmDate: alarm,
                routineMinutes: routineMinutes,
                commuteMinutes: commuteMinutes,
                firstEvent: nil
            )
        }

        // Step 3: Historical average wake time for this weekday
        // Wake times already reflect how early the user needed to be up,
        // so routine + commute are not subtracted again.
        if let avgWake = SleepHistoryStore.shared.averageWakeTime(forWeekday: tomorrowWeekday) {
            return BaselineAlarmResolution(
                alarmDate: tomorrowAt(hour: avgWake.hour, minute: avgWake.minute),
                routineMinutes: routineMinutes,
                commuteMinutes: commuteMinutes,
                firstEvent: nil
            )
        }

        // Step 4: 8 AM hard fallback (cold-start, no data yet)
        return BaselineAlarmResolution(
            alarmDate: tomorrowAt(hour: 8, minute: 0).addingTimeInterval(-buffer),
            routineMinutes: routineMinutes,
            commuteMinutes: commuteMinutes,
            firstEvent: nil
        )
    }

    // ── Rest period helpers ───────────────────────────────────

    /// Maps a Date to Lunifer's weekday ID string ("sun"…"sat").
    private func weekdayID(for date: Date) -> String {
        let ids = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        return ids[Calendar.current.component(.weekday, from: date) - 1]
    }

    /// Number of consecutive no-alarm days beginning tomorrow.
    private var consecutiveRestDaysFromTomorrow: Int {
        // Reference ticker so SwiftUI re-evaluates this each minute.
        _ = ticker
        var count = 0
        var check = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        while !answers.wakeDays.contains(weekdayID(for: check)) {
            count += 1
            check = Calendar.current.date(byAdding: .day, value: 1, to: check)!
            if count > 7 { break }   // guard against all-days-off edge case
        }
        return count
    }

    /// Rest screen is active once today's alarm has passed (noon minimum)
    /// and at least one no-alarm day follows.
    private var isRestPeriodActive: Bool {
        guard luniferEnabled else { return false }
        guard consecutiveRestDaysFromTomorrow > 0 else { return false }
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        return Date() >= max(calculatedAlarmDate, noon)
    }

    /// True when tomorrow is not in the user's scheduled wake days.
    /// Used to prevent AlarmKit from registering an alarm on rest days.
    private var isTomorrowRestDay: Bool {
        consecutiveRestDaysFromTomorrow > 0
    }

    // ── Commute helpers ───────────────────────────────────────

    private var isCommuterUser: Bool {
        answers.lifestyle == "student" || answers.lifestyle == "commuter"
    }

    /// True after the alarm has fired and before the calculated leave time,
    /// on a day the user is scheduled to wake up.
    private var shouldShowCommuteCard: Bool {
        _ = ticker // re-evaluate each minute alongside the rest-period check
        guard isCommuterUser else { return false }
        guard answers.wakeDays.contains(weekdayID(for: Date())) else { return false }
        // Only show while the user is between waking up and their first event starting.
        // If there is no calendar event today, the card (and nudge) are not shown.
        guard let firstEvent = CalendarManager.shared.todayEvents.first else { return false }
        let now = Date()
        return now >= calculatedAlarmDate && now < firstEvent.startDate
    }

    /// Day name of the next day Lunifer will set an alarm for after the rest period.
    private var nextAlarmDay: String? {
        let skip = consecutiveRestDaysFromTomorrow
        var check = Calendar.current.date(byAdding: .day, value: skip + 1, to: Date())!
        for _ in 0..<8 {
            if answers.wakeDays.contains(weekdayID(for: check)) {
                let df = DateFormatter()
                df.dateFormat = "EEEE"
                return df.string(from: check)
            }
            check = Calendar.current.date(byAdding: .day, value: 1, to: check)!
        }
        return nil
    }

    // ─────────────────────────────────────────────────────────

    private var tomorrowDateString: String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: tomorrow)
    }

    /// Recommended bedtime shown beneath the alarm time.
    /// If the user said "let Lunifer learn this" in the survey, uses the
    /// age-based recommendation from SleepDurationModel. Otherwise uses
    /// exactly what the user entered.
    private var bedtimeString: String {
        let alarmDate = overrideActive ? overrideTime : calculatedAlarmDate

        let sleepHours = WearableRecommendationStore.recommendedHours(
            from: WearableRecommendationStore.currentSources(),
            fallback: answers
        )

        let bedtime = alarmDate.addingTimeInterval(-sleepHours * 3600)

        let adjusted: Date
        if bedtime < Date() {
            adjusted = Calendar.current.date(byAdding: .day, value: 1, to: bedtime) ?? bedtime
        } else {
            adjusted = bedtime
        }

        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: adjusted)
    }

    var body: some View {
        ZStack {
            LuniferBackground()

            // ── Horizontal paging TabView ─────────────────
            // Sleep insights is on the left (page 0) so swiping
            // left-to-right from the alarm page reveals it.
            TabView(selection: $currentPage) {

                // PAGE 0: Sleep insights (left)
                SleepInsights(answers: $answers)
                    .tag(0)

                // PAGE 1: Alarm dashboard or rest screen
                Group {
                    if isRestPeriodActive {
                        restPage
                    } else {
                        alarmPage
                    }
                }
                .tag(1)
                .animation(.easeInOut(duration: 0.6), value: isRestPeriodActive)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)
            .ignoresSafeArea()

            // ── Page indicator dots ──────────────────────
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index
                                ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.9)
                                : Color.white.opacity(0.25))
                            .frame(width: 7, height: 7)
                            .animation(.easeInOut(duration: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 28)
            }

            // ── Dim overlay when Lunifer is off ──────────────
            Color.black
                .opacity(luniferEnabled ? 0 : 0.45)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.5), value: luniferEnabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSettings) {
            LuniferSettings(answers: $answers)
        }
        .sheet(isPresented: $showSound) {
            SoundSettingsView()
        }
        .task {
            // Restore persisted override time, or clear it if the alarm has already passed.
            if overrideActive && overrideTimestamp > 0 {
                let savedTime = Date(timeIntervalSince1970: overrideTimestamp)
                if savedTime < Date() {
                    overrideActive = false
                    overrideTimestamp = 0
                } else {
                    overrideTime = savedTime
                }
            }
            if overrideActive {
                AdaptiveAlarmStore.shared.clearPendingDecision()
            }
            // Load persisted added alarms. One-shots whose time has passed are
            // removed; repeating alarms are advanced to their next occurrence.
            loadAddedAlarms()
            let now = Date()
            var alarmsToReschedule: [(alarm: AddedAlarm, newDate: Date)] = []
            addedAlarms = addedAlarms.compactMap { alarm in
                guard alarm.date < now else { return alarm }
                if alarm.repeatDays.isEmpty {
                    // One-shot and in the past — delete from AlarmKit and storage.
                    Task { await LuniferAlarm.shared.cancelAddedAlarm(id: alarm.id) }
                    return nil
                } else {
                    // Repeating — advance timestamp to next qualifying weekday.
                    if let nextDate = nextOccurrence(after: now, repeatDays: alarm.repeatDays, timeOf: alarm.date) {
                        var advanced = alarm
                        advanced.timestamp = nextDate.timeIntervalSince1970
                        alarmsToReschedule.append((alarm: advanced, newDate: nextDate))
                        return advanced
                    } else {
                        Task { await LuniferAlarm.shared.cancelAddedAlarm(id: alarm.id) }
                        return nil
                    }
                }
            }
            saveAddedAlarms()
            for pair in alarmsToReschedule {
                Task { await LuniferAlarm.shared.scheduleAddedAlarm(
                    for: pair.newDate,
                    alarmID: pair.alarm.id,
                    snoozeMinutes: pair.alarm.snoozeMinutes
                )}
            }
            // Skip system-service calls (AlarmKit, CoreMotion, notifications)
            // when running inside the Xcode preview canvas.
            guard !isRunningPreview else { return }

            // Resolve the alarm date before starting any services so that the
            // wake notification and commute polling all use the same target.
            resolvedAlarmDate = await resolveAlarmDate()

            await SleepTracker.shared.startTracking()
            BatteryAlarmNotification.shared.startMonitoring()
            LuniferAlarm.shared.startAdaptiveRescheduling()
            await WakeNotification.shared.schedule(wakeDate: calculatedAlarmDate, answers: answers)
            await BirthdayNotification.shared.schedule(answers: answers)
            // Request alarm authorization — waits for the user to respond
            await LuniferAlarm.shared.requestAuthorization()

            checkAlarmAuthorization()

            // Schedule the Lunifer alarm from the resolved date if Lunifer is enabled,
            // the user has not set a manual override, and tomorrow is a wake day.
            // If tomorrow is a rest day, cancel any existing alarm so AlarmKit doesn't
            // fire on a day the user has marked as off.
            if luniferEnabled && !overrideActive {
                if isTomorrowRestDay {
                    AdaptiveAlarmStore.shared.clearPendingDecision()
                    await LuniferAlarm.shared.cancelAlarm()
                } else {
                    let routineMins = answers.routine.auto
                        ? 60
                        : answers.routine.hours * 60 + answers.routine.minutes
                    let commuteMins: Int = (answers.lifestyle == "student" || answers.lifestyle == "commuter")
                        ? (answers.commute.auto
                            ? (CommuteManager.shared.currentDurationMinutes > 0
                                ? CommuteManager.shared.currentDurationMinutes
                                : 30)
                            : answers.commute.hours * 60 + answers.commute.minutes)
                        : 0
                    await LuniferAlarm.shared.scheduleAlarm(
                        for: resolvedAlarmDate,
                        eventTitle: CalendarManager.shared.firstEventTomorrow?.title ?? "your first event",
                        routineMinutes: routineMins,
                        commuteMinutes: commuteMins
                    )
                }
            } else {
                AdaptiveAlarmStore.shared.clearPendingDecision()
            }

            // Small delay so the motion permission prompt has time to resolve
            // before we check the result
            try? await Task.sleep(nanoseconds: 500_000_000)
            checkMotionAuthorization()

            // Start commute monitoring on scheduled wake days for commuters/students.
            // fetchEvents() was already called inside resolveAlarmDate(), so
            // firstEventTomorrow is populated. Use the event start as the arrival
            // target; fall back to wake time + buffer when no event is found.
            if isCommuterUser && answers.wakeDays.contains(weekdayID(for: Date())) {
                let arrival = CalendarManager.shared.firstEventTomorrow?.startDate
                    ?? resolvedAlarmDate.addingTimeInterval(bufferSeconds())
                CommuteManager.shared.startPolling(answers: answers, arrivalDate: arrival)
            }

            // ── Rest-day early-event check ────────────────────
            // If tomorrow is a scheduled rest day but the user's calendar
            // has an event starting before 10:00 AM, prompt them to let
            // Lunifer set an alarm. The notification fires at 7 PM (or
            // immediately if the app is opened after 7 PM). Only one
            // notification is sent per calendar day.
            if consecutiveRestDaysFromTomorrow > 0 {
                await CalendarManager.shared.fetchEvents()
                if let event = CalendarManager.shared.firstEventTomorrow {
                    let cal = Calendar.current
                    let eventMinuteOfDay = cal.component(.hour, from: event.startDate) * 60
                        + cal.component(.minute, from: event.startDate)
                    if eventMinuteOfDay < 10 * 60 {
                        RestDayEventNotification.shared.scheduleIfNeeded(
                            event: event,
                            answers: answers
                        )
                    }
                }
            }
        }
        // Re-evaluate rest period every minute so the midnight transition
        // back to the alarm view happens automatically without a relaunch.
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            ticker = date
        }
        // Re-check both authorizations each time the user returns to the app
        // (e.g. coming back from iOS Settings after granting access).
        // Also run an immediate adaptive check so a calendar event added while
        // the app was suspended is reflected right away rather than waiting for
        // the next 5-minute timer tick.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            guard !isRunningPreview else { return }
            checkAlarmAuthorization()
            checkMotionAuthorization()
            guard luniferEnabled && !overrideActive else { return }
            Task { await LuniferAlarm.shared.checkAlarmAgainstCalendar() }
        }
        // Reload added alarms whenever stopAlarm() removes a one-shot or advances a repeating alarm.
        .onReceive(NotificationCenter.default.publisher(for: .luniferAddedAlarmModified)) { _ in
            loadAddedAlarms()
        }
        .alert("Alarm Access Required", isPresented: $showAlarmDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Lunifer needs Alarm access to wake you up. Please tap Open Settings and allow it under Alarms & Reminders.")
        }
        .alert("Motion & Fitness Access Required", isPresented: $showMotionDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Lunifer needs Motion & Fitness access to accurately track your sleep. Please tap Open Settings and allow it under Motion & Fitness.")
        }
    }

    private func checkAlarmAuthorization() {
        guard !isRunningPreview else {
            showAlarmDeniedAlert = false
            return
        }
        showAlarmDeniedAlert = LuniferAlarm.shared.authorizationDenied
    }

    // Checks CoreMotion authorization and surfaces the alert if denied.
    // Called on first load and every time the app returns to the foreground
    // so the loop continues until the user grants access.
    private func checkMotionAuthorization() {
        guard !isRunningPreview else {
            showMotionDeniedAlert = false
            return
        }
        let status = CMMotionActivityManager.authorizationStatus()
        showMotionDeniedAlert = (status == .denied)
    }

    // ── MARK: Alarm page (extracted from old body) ───────

    private var alarmPage: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            // ── Top bar: + button (left) and settings (right) ────
            VStack {
                HStack {
                    // + / Add Alarm button
                    // First tap: expand + into the "Add Alarm" label.
                    // Second tap (on the label): open the full-screen sheet.
                    Button {
                        if addAlarmTapped {
                            // Already showing label — open the sheet
                            // Default to 1 hour from now so the picker always starts
                            // at a valid future time rather than a fixed 8:00 AM.
                            addedAlarmPickerTime = Calendar.current.date(
                                byAdding: .hour, value: 1, to: Date()
                            ) ?? Date()
                            showAddAlarmSheet = true
                        } else {
                            // First tap — just reveal the label
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                addAlarmTapped = true
                            }
                        }
                    } label: {
                        if addAlarmTapped {
                            Text("Add Alarm")
                                .font(.custom("DM Sans", size: 13))
                                .foregroundColor(Color.white.opacity(0.85))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.08))
                                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                                )
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .light))
                                .foregroundColor(Color.white.opacity(0.85))
                                .padding(14)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.08))
                                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                                )
                        }
                    }
                    .padding(20)
                    .padding(.horizontal, 40)

                    Spacer()

                    // Settings button
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.85))
                            .padding(14)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                            )
                            .padding(20)
                            .padding(.horizontal, 40)
                    }
                }
                Spacer()
            }
            .opacity(luniferEnabled ? 1 : 0)
            .allowsHitTesting(luniferEnabled)

            // ── Wake-up time ──────────────────────────────
            // GeometryReader pins the alarm header at a fixed vertical position
            // (screen center − 32) using a fixed-height spacer above it.
            // The dropdown content lives in a ScrollView below the header so
            // the alarm time never moves when the user opens or closes the menu.
            GeometryReader { geo in
                VStack(spacing: 0) {
                    // Fixed spacer: positions alarm block center at geo.height/2 − 72,
                    // matching the original centred layout with a 40pt upward shift.
                    // 85 ≈ half the collapsed alarm-header height (label + dividers + time row + bedtime row).
                    Spacer()
                        .frame(height: max(0, geo.size.height / 2 - 72 - 85))

                    // ── Alarm header — never moves ────────────
                    VStack(spacing: 12) {
                        Text("TOMORROW'S ALARM")
                            .font(.custom("DM Sans", size: 11))
                            .foregroundColor(Color.white.opacity(0.35))
                            .kerning(2.5)

                        // ── Divider above ─────────────────────────
                        Rectangle()
                            .fill(Color.white.opacity(0.95))
                            .frame(height: 1)

                        // ── Tappable alarm time row ───────────────
                        ZStack {
                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                Text(wakeUpTime)
                                    .font(.libreFranklin(size: 63))
                                    .foregroundColor(Color.white.opacity(0.95))
                                    .monospacedDigit()
                                    .minimumScaleFactor(0.5)
                                    .lineLimit(1)
                                Text(wakeUpPeriod)
                                    .font(.libreFranklin(size: 60))
                                    .foregroundColor(Color.white.opacity(0.95))
                            }
                            .frame(maxWidth: .infinity, alignment: .center)

                            HStack {
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(Color.white.opacity(0.95))
                                    .rotationEffect(.degrees(alarmExpanded ? 90 : 0))
                                    .animation(.easeInOut(duration: 0.3), value: alarmExpanded)
                                    .padding(.trailing, 24)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                if !alarmExpanded {
                                    // Seed the picker to the calculated time so it starts
                                    // in the right place, but do NOT activate override here.
                                    // Override only activates when the user actually moves
                                    // the picker to a different time (see onChange below).
                                    if !overrideActive {
                                        overrideTime = calculatedAlarmDate
                                    }
                                }
                                alarmExpanded.toggle()
                            }
                        }

                        // ── Divider below ─────────────────────────
                        Rectangle()
                            .fill(Color.white.opacity(0.95))
                            .frame(height: 1)

                        // ── Bedtime → wake row ────────────────────
                        if !alarmExpanded {
                            HStack(spacing: 6) {
                                Text(bedtimeString)
                                    .font(.custom("DM Sans", size: 12))
                                    .foregroundColor(Color.white.opacity(0.35))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .light))
                                    .foregroundColor(Color.white.opacity(0.25))
                                Text("\(wakeUpTime) \(wakeUpPeriod)")
                                    .font(.custom("DM Sans", size: 12))
                                    .foregroundColor(Color.white.opacity(0.35))
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 8)
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 32)
                    .onChange(of: overrideTime) { _, newTime in
                        if overrideActive {
                            // Already in override — reschedule whenever the picker moves.
                            overrideTimestamp = newTime.timeIntervalSince1970
                            Task {
                                AdaptiveAlarmStore.shared.clearPendingDecision()
                                await LuniferAlarm.shared.scheduleAlarm(for: newTime)
                                await WakeNotification.shared.schedule(wakeDate: newTime, answers: answers)
                            }
                        } else {
                            // Not yet in override. The picker fires onChange when it is
                            // first seeded to calculatedAlarmDate (on dropdown open) —
                            // that should not activate override. Only activate when the
                            // user has meaningfully scrolled away from the calculated time
                            // (more than 60 seconds difference accounts for sub-minute
                            // precision in calculatedAlarmDate vs. the picker's minute snap).
                            let diffSeconds = abs(newTime.timeIntervalSince(calculatedAlarmDate))
                            guard diffSeconds > 60 else { return }
                            overrideActive = true
                            overrideTimestamp = newTime.timeIntervalSince1970
                            Task {
                                AdaptiveAlarmStore.shared.clearPendingDecision()
                                await LuniferAlarm.shared.scheduleAlarm(for: newTime)
                                await WakeNotification.shared.schedule(wakeDate: newTime, answers: answers)
                            }
                        }
                    }

                    // ── Dropdown content (below alarm header, scrollable) ──
                    if alarmExpanded {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 16) {
                                Text("Set custom time")
                                    .font(.custom("DM Sans", size: 14))
                                    .foregroundColor(Color.white.opacity(0.85))
                                    .frame(maxWidth: .infinity, alignment: .center)

                                DatePicker("", selection: $overrideTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.wheel)
                                    .labelsHidden()
                                    .colorScheme(.dark)
                                    .frame(maxWidth: .infinity)

                                Button {
                                    showSound = true
                                } label: {
                                    HStack {
                                        Text("Sound")
                                            .font(.custom("DM Sans", size: 14))
                                            .foregroundColor(Color.white.opacity(0.85))
                                        Spacer()
                                        Text(SoundOption.displayName(for: selectedAlarmSound))
                                            .font(.custom("DM Sans", size: 13))
                                            .foregroundColor(Color.white.opacity(0.4))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .light))
                                            .foregroundColor(Color.white.opacity(0.35))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.04))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)

                                // ── Snooze row ────────────────────────
                                VStack(spacing: 8) {
                                    HStack {
                                        Text("Snooze")
                                            .font(.custom("DM Sans", size: 14))
                                            .foregroundColor(Color.white.opacity(0.85))
                                        Spacer()
                                        Text("\(mainAlarmSnoozeMinutes) min")
                                            .font(.custom("DM Sans", size: 13))
                                            .foregroundColor(Color(red: 0.706, green: 0.588, blue: 0.902))
                                            .monospacedDigit()
                                    }
                                    Slider(value: Binding(
                                        get: { Double(mainAlarmSnoozeMinutes) },
                                        set: { mainAlarmSnoozeMinutes = Int($0.rounded()) }
                                    ), in: 1...30, step: 1)
                                    .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
                                    HStack {
                                        Text("1 min")
                                        Spacer()
                                        Text("30 min")
                                    }
                                    .font(.custom("DM Sans", size: 11))
                                    .foregroundColor(Color.white.opacity(0.2))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.04))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                        )
                                )
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 52)
                        }
                        .transition(.opacity.combined(with: .offset(y: -8)))
                    }

                    // ── Added Alarm cards ─────────────────────
                    // Each row is a Button that opens EditAddedAlarmSheet on tap.
                    // Swiping the row right-to-left reveals a Delete button at the
                    // right edge of the screen; tapping Delete removes the alarm.
                    if !addedAlarms.isEmpty && !alarmExpanded {
                        VStack(spacing: 0) {
                            Text("ADDED ALARMS")
                                .font(.custom("DM Sans", size: 10))
                                .foregroundColor(Color.white.opacity(0.3))
                                .kerning(2.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 60)
                                .padding(.top, 20)
                                .padding(.bottom, 4)

                            ForEach(addedAlarms.sorted { $0.timestamp < $1.timestamp }) { alarm in
                                AddedAlarmRow(
                                    alarm: alarm,
                                    onTap: { startEditingAddedAlarm(alarm) },
                                    onDelete: { deleteAddedAlarm(id: alarm.id) }
                                )
                                .padding(.bottom, 8)
                            }
                        }
                        .offset(y: luniferEnabled ? 0 : 8)
                    }

                    // ── Commute card ──────────────────────────
                    if shouldShowCommuteCard && !alarmExpanded {
                        CommuteStatusCard(answers: answers, alarmDate: calculatedAlarmDate)
                            .transition(.opacity)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .opacity(luniferEnabled ? 1 : 0)
            .allowsHitTesting(luniferEnabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $showAddAlarmSheet, onDismiss: {
                withAnimation { addAlarmTapped = false }
            }) {
                AddAlarmSheet(
                    pickerTime: $addedAlarmPickerTime,
                    onSet: { time, label, sound, snooze, repeatDays in
                        let alarm = AddedAlarm(
                            id: UUID(),
                            timestamp: time.timeIntervalSince1970,
                            label: label,
                            sound: sound,
                            snoozeMinutes: snooze,
                            repeatDays: repeatDays
                        )
                        withAnimation(.easeInOut(duration: 0.25)) {
                            addedAlarms.append(alarm)
                        }
                        saveAddedAlarms()
                        showAddAlarmSheet = false
                        Task { await LuniferAlarm.shared.scheduleAddedAlarm(for: time, alarmID: alarm.id, snoozeMinutes: snooze) }
                    },
                    onCancel: {
                        showAddAlarmSheet = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color(red: 0.06, green: 0.03, blue: 0.14))
            }
            .sheet(isPresented: $showEditAlarmSheet, onDismiss: {
                editingAlarmID = nil
            }) {
                EditAddedAlarmSheet(
                    pickerTime:    $editPickerTime,
                    sound:         $editSound,
                    snoozeMinutes: $editSnoozeMinutes,
                    repeatDays:    $editRepeatDays,
                    onSave:   { commitEditingAddedAlarm() },
                    onCancel: { showEditAlarmSheet = false }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color(red: 0.06, green: 0.03, blue: 0.14))
            }

            // ── Unified toggle button — travels from bottom to center ──
            if !alarmExpanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.5)) { luniferEnabled.toggle() }
                    if !luniferEnabled {
                        Task {
                            AdaptiveAlarmStore.shared.clearPendingDecision()
                            await LuniferAlarm.shared.cancelAlarm()
                            WakeNotification.shared.cancel()
                            BatteryAlarmNotification.shared.cancelWarning()
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: luniferEnabled ? "moon.fill" : "moon.stars.fill")
                            .font(.system(size: luniferEnabled ? 13 : 15))
                            .foregroundColor(luniferEnabled
                                ? Color(red: 0.706, green: 0.588, blue: 0.902)
                                : Color.white.opacity(0.6))
                        Text(luniferEnabled ? "Turn Lunifer off" : "Turn on Lunifer")
                            .font(.custom("DM Sans", size: luniferEnabled ? 14 : 15))
                            .foregroundColor(luniferEnabled
                                ? Color.white.opacity(0.6)
                                : Color.white.opacity(0.7))
                    }
                    .padding(.horizontal, luniferEnabled ? 24 : 32)
                    .padding(.vertical, luniferEnabled ? 12 : 16)
                    .background(
                        Capsule()
                            .fill(luniferEnabled
                                ? Color(red: 0.392, green: 0.275, blue: 0.627).opacity(0.2)
                                : Color.white.opacity(0.08))
                            .overlay(Capsule().stroke(luniferEnabled
                                ? Color(red: 0.627, green: 0.471, blue: 0.863).opacity(0.3)
                                : Color.white.opacity(0.25), lineWidth: luniferEnabled ? 1 : 1.5))
                    )
                }
                .padding(.bottom, luniferEnabled ? 52 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: luniferEnabled ? .bottom : .center)
                .animation(.easeInOut(duration: 0.5), value: luniferEnabled)
            }

            // ── Debug button — bottom left ────────────────────────
            if !alarmExpanded && luniferEnabled {
                Button { showDebug = true } label: {
                    Text("Debug")
                        .font(.custom("DM Sans", size: 13))
                        .foregroundColor(Color.white.opacity(0.4))
                        .padding(.horizontal, 19)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.05))
                                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 32)
                .padding(.bottom, 52)
            }
        }
        // Dismiss the expanded "Add Alarm" label when the user taps
        // anywhere on the page that isn't the button itself.
        .sheet(isPresented: $showDebug) {
            LuniferDebugView()
                .presentationBackground(Color(red: 0.06, green: 0.03, blue: 0.14))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard addAlarmTapped else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                addAlarmTapped = false
            }
        }
    }

    // ── MARK: Rest period page ────────────────────────────────────
    // Shown in place of the alarm page on evenings before no-alarm days.
    // Design intent: calming, unhurried — a contrast to the precision of
    // the alarm view. Large soft typography, muted palette, no countdown.

    private var restPage: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            // ── Settings button ───────────────────────────
            VStack {
                HStack {
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.85))
                            .padding(14)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                            )
                            .padding(20)
                            .padding(.horizontal, 40)
                    }
                    Spacer().frame(width: 0)
                }
                Spacer()
            }

            // ── Centre content ────────────────────────────
            VStack(spacing: 0) {

                Text("No Alarm tomorrow")
                    .font(.custom("Cormorant Garamond", size: 42).weight(.light))
                    .foregroundColor(Color.white.opacity(0.90))
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 32)

                Rectangle()
                    .fill(Color.white.opacity(0.95))
                    .frame(height: 1)
                    .padding(.horizontal, 32)

                Spacer().frame(height: 28)

                if let day = nextAlarmDay {
                    Text("Next Alarm \(day)")
                        .font(.custom("DM Sans", size: 14))
                        .foregroundColor(Color.white.opacity(0.35))
                }
            }
            .padding(.horizontal, 32)
            .offset(y: -32)
        }
    }
}

// ── MARK: Weekday repeat helpers ──────────────────────────────

private struct WeekdayOption: Identifiable {
    let id: String      // "mon" … "sun"
    let letter: String  // "M" "T" "W" "T" "F" "S" "S"
}

private let weekdayOptions: [WeekdayOption] = [
    WeekdayOption(id: "mon", letter: "M"),
    WeekdayOption(id: "tue", letter: "T"),
    WeekdayOption(id: "wed", letter: "W"),
    WeekdayOption(id: "thu", letter: "T"),
    WeekdayOption(id: "fri", letter: "F"),
    WeekdayOption(id: "sat", letter: "S"),
    WeekdayOption(id: "sun", letter: "S"),
]

private func repeatSummary(_ days: [String]) -> String {
    if days.count == 7 { return "Every day" }
    let order  = ["mon","tue","wed","thu","fri","sat","sun"]
    let labels = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
    return order.enumerated()
        .filter { days.contains($0.element) }
        .map    { labels[$0.offset] }
        .joined(separator: ", ")
}

// ── MARK: Add Alarm Sheet ─────────────────────────────────────

struct AddAlarmSheet: View {
    @Binding var pickerTime: Date
    let onSet:    (Date, String, String, Int, [String]) -> Void  // time, label, sound, snoozeMinutes, repeatDays
    let onCancel: () -> Void

    @State private var addedAlarmSound: String = "DeafultAlarm.wav"
    @State private var addedAlarmLabel: String = ""
    @State private var addedAlarmSnoozeMinutes: Int = 5
    @State private var addedAlarmRepeatDays: [String] = []
    @State private var repeatExpanded: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.03, blue: 0.14).ignoresSafeArea()

                VStack(spacing: 0) {

                    // ── Header ────────────────────────────────
                    HStack {
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(Color.white.opacity(0.45))
                        }
                        Spacer()
                        Text("Add Alarm")
                            .font(.custom("Cormorant Garamond", size: 28).weight(.light))
                            .foregroundColor(Color.white.opacity(0.90))
                        Spacer()
                        // Invisible balance element
                        Text("Cancel")
                            .font(.custom("DM Sans", size: 14))
                            .foregroundColor(.clear)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                    // ── Time picker ───────────────────────────
                    DatePicker("", selection: $pickerTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)

                    // ── Label row ─────────────────────────────
                    HStack {
                        Text("Label")
                            .font(.custom("DM Sans", size: 15))
                            .foregroundColor(Color.white.opacity(0.85))
                        Spacer()
                        TextField("Optional", text: $addedAlarmLabel)
                            .font(.custom("DM Sans", size: 14))
                            .foregroundColor(Color.white.opacity(0.55))
                            .multilineTextAlignment(.trailing)
                            .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
                            .submitLabel(.done)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)

                    // ── Sound row ─────────────────────────────
                    NavigationLink(destination: AddedAlarmSoundView(sound: $addedAlarmSound)) {
                        HStack {
                            Text("Sound")
                                .font(.custom("DM Sans", size: 15))
                                .foregroundColor(Color.white.opacity(0.85))
                            Spacer()
                            Text(SoundOption.displayName(for: addedAlarmSound))  // uses local @State
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(Color.white.opacity(0.35))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(Color.white.opacity(0.25))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)

                    // ── Snooze row ─────────────────────────────
                    VStack(spacing: 8) {
                        HStack {
                            Text("Snooze")
                                .font(.custom("DM Sans", size: 15))
                                .foregroundColor(Color.white.opacity(0.85))
                            Spacer()
                            Text("\(addedAlarmSnoozeMinutes) min")
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(Color(red: 0.706, green: 0.588, blue: 0.902))
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(addedAlarmSnoozeMinutes) },
                            set: { addedAlarmSnoozeMinutes = Int($0.rounded()) }
                        ), in: 1...30, step: 1)
                        .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
                        HStack {
                            Text("1 min")
                            Spacer()
                            Text("30 min")
                        }
                        .font(.custom("DM Sans", size: 11))
                        .foregroundColor(Color.white.opacity(0.2))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)

                    // ── Repeat row ────────────────────────────
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { repeatExpanded.toggle() }
                        } label: {
                            HStack {
                                Text("Repeat")
                                    .font(.custom("DM Sans", size: 15))
                                    .foregroundColor(Color.white.opacity(0.85))
                                Spacer()
                                Text(addedAlarmRepeatDays.isEmpty ? "Never" : repeatSummary(addedAlarmRepeatDays))
                                    .font(.custom("DM Sans", size: 14))
                                    .foregroundColor(Color.white.opacity(0.35))
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(Color.white.opacity(0.25))
                                    .rotationEffect(.degrees(repeatExpanded ? 90 : 0))
                                    .animation(.easeInOut(duration: 0.2), value: repeatExpanded)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.plain)

                        if repeatExpanded {
                            HStack(spacing: 0) {
                                ForEach(weekdayOptions) { option in
                                    let selected = addedAlarmRepeatDays.contains(option.id)
                                    Button {
                                        if selected {
                                            addedAlarmRepeatDays.removeAll { $0 == option.id }
                                        } else {
                                            addedAlarmRepeatDays.append(option.id)
                                        }
                                    } label: {
                                        Text(option.letter)
                                            .font(.custom("DM Sans", size: 13).weight(.medium))
                                            .foregroundColor(selected ? .white : Color.white.opacity(0.35))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 36)
                                            .background(
                                                Circle()
                                                    .fill(selected
                                                        ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.85)
                                                        : Color.white.opacity(0.07))
                                                    .frame(width: 36, height: 36)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                    Spacer()

                    // ── Set Alarm button ──────────────────────
                    Button {
                        onSet(pickerTime, addedAlarmLabel, addedAlarmSound, addedAlarmSnoozeMinutes, addedAlarmRepeatDays)
                    } label: {
                        Text("Set Alarm")
                            .font(.custom("DM Sans", size: 15).weight(.medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(LinearGradient(
                                        colors: [
                                            Color(red: 0.471, green: 0.314, blue: 0.863).opacity(0.9),
                                            Color(red: 0.314, green: 0.196, blue: 0.706).opacity(0.9),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// ── MARK: Added Alarm Sound Picker ────────────────────────────

struct AddedAlarmSoundView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var sound: String
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.06, green: 0.03, blue: 0.14).ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ────────────────────────────────
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(Color.white.opacity(0.75))
                            .frame(width: 36, height: 36)
                    }
                    Spacer()
                    Text("Sound")
                        .font(.custom("Cormorant Garamond", size: 28).weight(.light))
                        .foregroundColor(Color.white.opacity(0.9))
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                // ── Sound list ────────────────────────────
                VStack(spacing: 0) {
                    ForEach(SoundOption.all, id: \.filename) { option in
                        Button {
                            sound = option.filename
                            previewSound(option.filename)
                        } label: {
                            HStack {
                                Text(option.displayName)
                                    .font(.custom("DM Sans", size: 15))
                                    .foregroundColor(Color.white.opacity(0.85))
                                Spacer()
                                if sound == option.filename {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Color(red: 0.706, green: 0.588, blue: 0.902))
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.plain)

                        if option.filename != SoundOption.all.last?.filename {
                            Rectangle()
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 1)
                                .padding(.horizontal, 24)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func previewSound(_ filename: String) {
        audioPlayer?.stop()
        guard let url = Bundle.main.url(
            forResource: (filename as NSString).deletingPathExtension,
            withExtension: (filename as NSString).pathExtension
        ) else { return }
        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.play()
    }
}

// ── MARK: Added Alarm Row ─────────────────────────────────────
//
// Renders one added alarm on the dashboard with two interactions:
//   • Tap → opens EditAddedAlarmSheet via onTap.
//   • Right-to-left swipe → reveals a Delete button at the trailing
//     edge; tapping it calls onDelete.
//
// Layout strategy:
//   A GeometryReader hands us the row's actual width as `geo.size.width`,
//   which lets us position both children of a ZStack with explicit
//   offsets driven directly by `dragOffset`:
//
//     • Alarm content is full-width (geo.size.width × rowHeight) and
//       offset by `dragOffset` — at rest it occupies the row, at
//       dragOffset = -deleteWidth its right edge sits at
//       geo.size.width - deleteWidth.
//     • Delete button is fixed-width (deleteWidth × rowHeight) and
//       offset by `geo.size.width + dragOffset` — at rest its left
//       edge sits exactly at the row's right edge (off-screen), at
//       dragOffset = -deleteWidth its left edge sits at
//       geo.size.width - deleteWidth, fully on-screen.
//
//   This avoids the earlier overlay + nested-offset arithmetic that
//   left the button only partially visible, and the HStack-overflow
//   compression that hid it entirely.

private struct AddedAlarmRow: View {
    let alarm: AddedAlarm
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var revealed: Bool = false

    /// Width of the revealed Delete button. Sized so the red action area
    /// occupies a substantial portion of the row when the swipe locks
    /// open — comparable to standard iOS swipe actions but slightly
    /// wider so the action is unmistakable on this dashboard.
    private let deleteWidth: CGFloat = 140
    private let revealThreshold: CGFloat = 50

    /// Row height adapts to label and repeat-day presence so the layout
    /// stays compact when neither is set.
    private var rowHeight: CGFloat {
        let hasLabel  = !alarm.label.isEmpty
        let hasRepeat = alarm.displayRepeatDays != nil
        switch (hasLabel, hasRepeat) {
        case (false, false): return 56
        case (true,  false),
             (false, true):  return 78
        case (true,  true):  return 96
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {

                // ── Delete button (red, parked just past the right edge) ──
                Button(action: onDelete) {
                    Text("Delete")
                        .font(.custom("DM Sans", size: 14).weight(.medium))
                        .foregroundColor(.white)
                        .frame(width: deleteWidth, height: rowHeight)
                        .background(Color(red: 0.78, green: 0.22, blue: 0.28))
                }
                .buttonStyle(.plain)
                // At rest (dragOffset = 0): button sits at x = geo.size.width
                // (off-screen, just past the right edge).
                // Fully revealed (dragOffset = -deleteWidth): button sits at
                // x = geo.size.width - deleteWidth, anchored to the right edge.
                .offset(x: geo.size.width + dragOffset)

                // ── Alarm content (full row width) ─────────────────
                // Plain VStack + .onTapGesture (not a Button) so the parent
                // DragGesture is never preempted by a SwiftUI button's
                // internal tap recogniser.
                VStack(alignment: .leading, spacing: 2) {
                    if !alarm.label.isEmpty {
                        Text(alarm.label)
                            .font(.custom("DM Sans", size: 13))
                            .foregroundColor(Color.white.opacity(0.45))
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text(alarm.displayTime)
                            .font(.libreFranklin(size: 40))
                            .foregroundColor(Color.white.opacity(0.80))
                            .monospacedDigit()
                        Text(alarm.displayPeriod)
                            .font(.libreFranklin(size: 37))
                            .foregroundColor(Color.white.opacity(0.80))
                    }
                    if let repeatStr = alarm.displayRepeatDays {
                        Text("Repeats \(repeatStr)")
                            .font(.custom("DM Sans", size: 11))
                            .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.65))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 60)
                .padding(.trailing, 24)
                .frame(width: geo.size.width, height: rowHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    if revealed {
                        // First tap on a revealed row collapses the swipe.
                        withAnimation(.easeOut(duration: 0.25)) {
                            dragOffset = 0
                            revealed = false
                        }
                    } else {
                        onTap()
                    }
                }
                .offset(x: dragOffset)
            }
            .frame(width: geo.size.width, height: rowHeight, alignment: .topLeading)
            // ── Drag gesture ──────────────────────────────────────
            // .highPriorityGesture so this swipe beats the surrounding
            // TabView(.page) pager that owns the Sleep-Insights ↔ Alarm
            // paging gesture.
            .highPriorityGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        let dx = value.translation.width
                        // Ignore predominantly vertical drags so vertical
                        // ScrollView scrolling still works.
                        guard abs(dx) > abs(value.translation.height) else { return }
                        if revealed {
                            // From revealed state, allow rightward drag to close.
                            dragOffset = max(-deleteWidth, min(0, -deleteWidth + dx))
                        } else {
                            // From closed state, allow leftward drag to reveal.
                            // Small overshoot past -deleteWidth for a rubber-band feel.
                            dragOffset = max(-deleteWidth - 20, min(0, dx))
                        }
                    }
                    .onEnded { value in
                        let dx = value.translation.width
                        withAnimation(.easeOut(duration: 0.25)) {
                            if revealed {
                                if dx > revealThreshold {
                                    dragOffset = 0
                                    revealed = false
                                } else {
                                    dragOffset = -deleteWidth
                                }
                            } else {
                                if dx < -revealThreshold {
                                    dragOffset = -deleteWidth
                                    revealed = true
                                } else {
                                    dragOffset = 0
                                }
                            }
                        }
                    }
            )
        }
        .frame(height: rowHeight)
    }
}

// ── MARK: Edit Added Alarm Sheet ──────────────────────────────
//
// Sheet shown when the user taps an existing added-alarm row. Mirrors
// the three controls available in the calculated-alarm dropdown menu:
// time picker, sound picker, snooze slider. Bindings let the parent
// view seed and read back the edits without this sheet owning the
// underlying AddedAlarm value directly.

struct EditAddedAlarmSheet: View {
    @Binding var pickerTime: Date
    @Binding var sound: String
    @Binding var snoozeMinutes: Int
    @Binding var repeatDays: [String]
    let onSave:   () -> Void
    let onCancel: () -> Void

    @State private var repeatExpanded: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.03, blue: 0.14).ignoresSafeArea()

                VStack(spacing: 0) {

                    // ── Header ────────────────────────────────
                    HStack {
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(Color.white.opacity(0.45))
                        }
                        Spacer()
                        Text("Edit Alarm")
                            .font(.custom("Cormorant Garamond", size: 28).weight(.light))
                            .foregroundColor(Color.white.opacity(0.90))
                        Spacer()
                        Button(action: onSave) {
                            Text("Save")
                                .font(.custom("DM Sans", size: 14).weight(.medium))
                                .foregroundColor(Color(red: 0.706, green: 0.588, blue: 0.902))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                    // ── Time picker ───────────────────────────
                    DatePicker("", selection: $pickerTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)

                    // ── Sound row ─────────────────────────────
                    NavigationLink(destination: AddedAlarmSoundView(sound: $sound)) {
                        HStack {
                            Text("Sound")
                                .font(.custom("DM Sans", size: 15))
                                .foregroundColor(Color.white.opacity(0.85))
                            Spacer()
                            Text(SoundOption.displayName(for: sound))
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(Color.white.opacity(0.35))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(Color.white.opacity(0.25))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)

                    // ── Snooze row ────────────────────────────
                    VStack(spacing: 8) {
                        HStack {
                            Text("Snooze")
                                .font(.custom("DM Sans", size: 15))
                                .foregroundColor(Color.white.opacity(0.85))
                            Spacer()
                            Text("\(snoozeMinutes) min")
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(Color(red: 0.706, green: 0.588, blue: 0.902))
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(snoozeMinutes) },
                            set: { snoozeMinutes = Int($0.rounded()) }
                        ), in: 1...30, step: 1)
                        .tint(Color(red: 0.627, green: 0.471, blue: 1.0))
                        HStack {
                            Text("1 min")
                            Spacer()
                            Text("30 min")
                        }
                        .font(.custom("DM Sans", size: 11))
                        .foregroundColor(Color.white.opacity(0.2))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)

                    // ── Repeat row ────────────────────────────
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { repeatExpanded.toggle() }
                        } label: {
                            HStack {
                                Text("Repeat")
                                    .font(.custom("DM Sans", size: 15))
                                    .foregroundColor(Color.white.opacity(0.85))
                                Spacer()
                                Text(repeatDays.isEmpty ? "Never" : repeatSummary(repeatDays))
                                    .font(.custom("DM Sans", size: 14))
                                    .foregroundColor(Color.white.opacity(0.35))
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(Color.white.opacity(0.25))
                                    .rotationEffect(.degrees(repeatExpanded ? 90 : 0))
                                    .animation(.easeInOut(duration: 0.2), value: repeatExpanded)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.plain)

                        if repeatExpanded {
                            HStack(spacing: 0) {
                                ForEach(weekdayOptions) { option in
                                    let selected = repeatDays.contains(option.id)
                                    Button {
                                        if selected {
                                            repeatDays.removeAll { $0 == option.id }
                                        } else {
                                            repeatDays.append(option.id)
                                        }
                                    } label: {
                                        Text(option.letter)
                                            .font(.custom("DM Sans", size: 13).weight(.medium))
                                            .foregroundColor(selected ? .white : Color.white.opacity(0.35))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 36)
                                            .background(
                                                Circle()
                                                    .fill(selected
                                                        ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.85)
                                                        : Color.white.opacity(0.07))
                                                    .frame(width: 36, height: 36)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                    Spacer()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct SoundOption {
    let displayName: String
    let filename: String

    static let all: [SoundOption] = [
        SoundOption(displayName: "Default Alarm",      filename: "DeafultAlarm.wav"),
        SoundOption(displayName: "Alarm Clock",        filename: "Alarm Clock.mp3"),
        SoundOption(displayName: "Church Bells",       filename: "Church Bells.wav"),
        SoundOption(displayName: "Crystal Bowl",       filename: "Crystal Bowl Rythym audio .m4a"),
        SoundOption(displayName: "Space",              filename: "Space.wav"),
        SoundOption(displayName: "Twin Alarm Bell",    filename: "Twin Alarm Bell.wav"),
        SoundOption(displayName: "Clock Alarm",        filename: "microsammy-clock-alarm-8761.mp3"),
    ]

    static func displayName(for filename: String) -> String {
        all.first { $0.filename == filename }?.displayName ?? filename
    }
}

struct SoundSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedAlarmSound") private var selectedAlarmSound: String = "DeafultAlarm.wav"
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.luniferBg.ignoresSafeArea()
                StarsView()

                VStack(spacing: 0) {
                    // ── Header ────────────────────────────────
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .light))
                                .foregroundColor(Color.white.opacity(0.75))
                                .frame(width: 36, height: 36)
                        }
                        Spacer()
                        Text("Sound")
                            .font(.custom("Cormorant Garamond", size: 28).weight(.light))
                            .foregroundColor(Color.white.opacity(0.9))
                        Spacer()
                        Color.clear.frame(width: 36, height: 36)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                    // ── Sound list ────────────────────────────
                    VStack(spacing: 0) {
                        ForEach(SoundOption.all, id: \.filename) { option in
                            Button {
                                selectedAlarmSound = option.filename
                                preview(option.filename)
                            } label: {
                                HStack {
                                    Text(option.displayName)
                                        .font(.custom("DM Sans", size: 15))
                                        .foregroundColor(Color.white.opacity(0.85))
                                    Spacer()
                                    if selectedAlarmSound == option.filename {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(Color(red: 0.706, green: 0.588, blue: 0.902))
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(.plain)

                            if option.filename != SoundOption.all.last?.filename {
                                Rectangle()
                                    .fill(Color.white.opacity(0.07))
                                    .frame(height: 1)
                                    .padding(.horizontal, 24)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

// ── MARK: Preview ─────────────────────────────────────────────


    private func preview(_ filename: String) {
        audioPlayer?.stop()
        guard let url = Bundle.main.url(forResource: (filename as NSString).deletingPathExtension,
                                        withExtension: (filename as NSString).pathExtension) else { return }
        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.play()
    }
}
// CommuteStatusCard lives in LuniferCommuteDashboard.swift

// ── MARK: Debug View ──────────────────────────────────────────

struct LuniferDebugView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var pendingDecision: AdaptiveAlarmDecision? = nil
    @State private var recentOutcomes: [AdaptiveAlarmOutcome] = []
    @State private var alarmEvents: [DebugAlarmEvent] = []
    @State private var baselineStep: String = "—"

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    private static let fullFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm:ss a"; return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE MMM d"; return f
    }()

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.03, blue: 0.14).ignoresSafeArea()
            LuniferBackground()

            VStack(spacing: 0) {
                // ── Header ────────────────────────────────────
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(Color.white.opacity(0.6))
                            .padding(12)
                    }
                    Spacer()
                    Text("Debug")
                        .font(.custom("Cormorant Garamond", size: 28).weight(.light))
                        .foregroundColor(Color.white.opacity(0.9))
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 25)
                .padding(.top, 12)
                .padding(.bottom, 4)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        alarmCalcSection
                        banditSection
                        commuteSection
                        sleepSection
                        outcomesSection
                        eventsSection
                    }
                    .padding(.horizontal, 25)
                    .padding(.vertical, 16)
                    .padding(.bottom, 48)
                }
            }
        }
        .ignoresSafeArea()
        .task { await loadData() }
    }

    // ── Data loading ──────────────────────────────────────────

    @MainActor
    private func loadData() async {
        await CalendarManager.shared.fetchEvents()
        pendingDecision = AdaptiveAlarmStore.shared.pendingDecision()
        recentOutcomes  = AdaptiveAlarmStore.shared.recentOutcomes(limit: 3)
        alarmEvents     = Array(DebugAlarmEventStore.shared.load().reversed())

        let cal      = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let wd       = cal.component(.weekday, from: tomorrow)

        if CalendarManager.shared.firstEventTomorrow != nil {
            baselineStep = "Step 1 — Calendar event"
        } else if CalendarManager.shared.typicalFirstEventTime(forWeekday: wd) != nil {
            baselineStep = "Step 2 — Historical event pattern"
        } else if SleepHistoryStore.shared.averageWakeTime(forWeekday: wd) != nil {
            baselineStep = "Step 3 — Historical wake average"
        } else {
            baselineStep = "Step 4 — 8 AM fallback"
        }
    }

    // ── Sections ──────────────────────────────────────────────

    private var alarmCalcSection: some View {
        card("Alarm Calculation") {
            row("Baseline source", baselineStep)
            if let event = CalendarManager.shared.firstEventTomorrow {
                sep
                row("Driving event", event.title)
                sep
                row("Event starts", Self.timeFmt.string(from: event.startDate))
            }
            if let d = pendingDecision {
                sep
                row("Baseline alarm", Self.timeFmt.string(from: d.baselineAlarm))
                sep
                let off = d.selectedOffsetMinutes
                row("Adaptive offset",
                    off == 0 ? "0 min" : (off > 0 ? "+\(off) min" : "\(off) min"),
                    tint: off != 0)
                sep
                row("Final alarm", Self.timeFmt.string(from: d.finalAlarm), tint: true)
                sep
                row("Safety clamped", d.wasClamped ? "Yes" : "No")
            } else {
                sep
                row("Decision", "None — override or rest day")
            }
        }
    }

    private var banditSection: some View {
        card("Adaptive Bandit") {
            row("Outcomes stored", "\(AdaptiveAlarmStore.shared.recentOutcomes().count) / 120")
            if let d = pendingDecision {
                sep
                row("Offset chosen", "\(d.selectedOffsetMinutes) min")
                sep
                row("Expected reward", String(format: "%.3f", d.expectedReward))
                sep
                row("Uncertainty",     String(format: "%.3f", d.uncertainty))
                sep
                row("Training eligible", d.trainingEligible ? "Yes" : "No",
                    tint: !d.trainingEligible)
                sep
                row("Sleep debt", String(format: "%.2f hrs", d.context.sleepDebtHours))
                sep
                row("Wearable active", d.context.hasWearable ? "Yes" : "No")
            } else {
                sep
                row("Decision", "None")
            }
        }
    }

    private var commuteSection: some View {
        card("Commute") {
            let dur = CommuteManager.shared.currentDurationMinutes
            row("Duration", dur > 0 ? "\(dur) min" : "0 min (fallback)")
            sep
            row("Last fetched",
                CommuteManager.shared.lastFetched.map { Self.fullFmt.string(from: $0) } ?? "Never",
                tint: CommuteManager.shared.lastFetched == nil)
            sep
            let loc = CalendarManager.shared.firstEventTomorrow?.location ?? ""
            row("Event location",
                loc.isEmpty ? "(none — routing disabled)" : loc,
                tint: loc.isEmpty)
            sep
            row("GPS fix",
                LocationManager.shared.currentCoordinate != nil ? "Available" : "Unavailable",
                tint: LocationManager.shared.currentCoordinate == nil)
        }
    }

    private var sleepSection: some View {
        card("Sleep Tracker") {
            let t = SleepTracker.shared
            row("Status", t.isAsleep ? "Asleep" : "Awake", tint: t.isAsleep)
            sep
            row("Sleep probability", String(format: "%.0f%%", t.sleepProbability * 100))
            sep
            row("Est. sleep onset",
                t.estimatedSleepOnset.map { Self.timeFmt.string(from: $0) } ?? "—")
            sep
            row("Est. wake time",
                t.estimatedWakeTime.map { Self.timeFmt.string(from: $0) } ?? "—")
            sep
            let last = SleepHistoryStore.shared.recentHistory(days: 1).first
            row("Last night",
                last.map { String(format: "%.1f hrs", $0.durationHours) } ?? "No data",
                tint: last == nil)
        }
    }

    private var outcomesSection: some View {
        let sorted = Array(recentOutcomes.reversed())
        return card("Recent Outcomes") {
            if sorted.isEmpty {
                row("Outcomes", "None recorded yet")
            } else {
                ForEach(sorted.indices, id: \.self) { i in
                    let o = sorted[i]
                    if i > 0 { sep }
                    VStack(spacing: 0) {
                        row(Self.dayFmt.string(from: o.observedAt),
                            o.outcome,
                            tint: o.outcome == "woke_before_alarm")
                        subRow("Offset", "\(o.selectedOffsetMinutes) min")
                        subRow("Reward", String(format: "%.3f", o.reward))
                        if let hrs = o.actualSleepHours {
                            subRow("Sleep hrs", String(format: "%.1f", hrs))
                        }
                    }
                }
            }
        }
    }

    private var eventsSection: some View {
        let events = Array(alarmEvents.prefix(20))
        return card("Alarm Events") {
            if events.isEmpty {
                row("Events", "None recorded yet")
            } else {
                ForEach(events.indices, id: \.self) { i in
                    let e = events[i]
                    if i > 0 { sep }
                    VStack(alignment: .leading, spacing: 0) {
                        row(eventLabel(e), Self.fullFmt.string(from: e.timestamp))
                        if let detail = e.detail {
                            subRow("", detail)
                        }
                    }
                }
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────

    private func eventLabel(_ e: DebugAlarmEvent) -> String {
        switch e.type {
        case "fired":      return "🔔 Fired"
        case "snoozed":    return "💤 Snoozed"
        case "dismissed":  return "✓  Dismissed"
        case "woke_before": return "☀️ Woke early"
        default:           return e.type.capitalized
        }
    }

    private func card<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.custom("DM Sans", size: 11))
                .foregroundColor(Color.white.opacity(0.35))
                .kerning(2)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1))
            )
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String, tint: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.custom("DM Sans", size: 13))
                .foregroundColor(Color.white.opacity(0.5))
            Spacer(minLength: 12)
            Text(value)
                .font(.custom("DM Sans", size: 13))
                .foregroundColor(tint
                    ? Color(red: 0.706, green: 0.588, blue: 0.902)
                    : Color.white.opacity(0.85))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 19)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func subRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.custom("DM Sans", size: 12))
                .foregroundColor(Color.white.opacity(0.3))
            Spacer(minLength: 8)
            Text(value)
                .font(.custom("DM Sans", size: 12))
                .foregroundColor(Color.white.opacity(0.45))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 19)
        .padding(.bottom, 8)
    }

    private var sep: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 19)
    }
}

private struct LuniferMainPreview: View {
    @State private var answers: SurveyAnswers = {
        var a = SurveyAnswers()
        a.age = "28"
        a.lifestyle = "commuter"
        a.wakeDays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        a.calendar = "apple"
        a.routine = TimeValue(hours: 0, minutes: 45, auto: false)
        a.commute = TimeValue(hours: 0, minutes: 30, auto: false)
        a.sleep = TimeValue(hours: 8, minutes: 0, auto: false)
        return a
    }()

    var body: some View {
        LuniferMain(answers: $answers)
    }
}

private struct SleepInsightsOnlyPreview: View {
    @State private var answers: SurveyAnswers = {
        var a = SurveyAnswers()
        a.age = "28"
        a.sleep = TimeValue(hours: 8, minutes: 0, auto: false)
        return a
    }()

    var body: some View {
        ZStack {
            Color.luniferBg.ignoresSafeArea()
            SleepInsights(answers: $answers, previewEntries: SleepHistoryMock.entries)
        }
    }
}

struct LuniferMain_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LuniferMainPreview()
                .previewDisplayName("Dashboard")

            SleepInsightsOnlyPreview()
                .previewDisplayName("Sleep Insights Only")
        }
    }
}

