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
    @AppStorage("snoozeMinutes") private var snoozeMinutes: Int = 5
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

    /// Returns the survey-derived routine + commute buffer in seconds.
    private func bufferSeconds() -> TimeInterval {
        let routine = answers.routine.auto
            ? 60
            : answers.routine.hours * 60 + answers.routine.minutes
        let commute: Int = (answers.lifestyle == "student" || answers.lifestyle == "commuter")
            ? (answers.commute.auto ? 30 : answers.commute.hours * 60 + answers.commute.minutes)
            : 0
        return Double(routine + commute) * 60
    }

    /// Builds a Date for today using the supplied hour and minute.
    private func todayAt(hour: Int, minute: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    /// Resolves the best alarm date for tomorrow using a 4-step fallback chain.
    /// Asynchronous because steps 1–2 may require a calendar fetch.
    private func resolveAlarmDate() async -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let tomorrowWeekday = cal.component(.weekday, from: tomorrow)
        let buffer = bufferSeconds()

        // Step 1: Live calendar event tomorrow
        await CalendarManager.shared.fetchEvents()
        if let event = CalendarManager.shared.firstEventTomorrow {
            return event.startDate.addingTimeInterval(-buffer)
        }

        // Step 2: Historical average first-event time for this weekday
        if let typical = CalendarManager.shared.typicalFirstEventTime(forWeekday: tomorrowWeekday) {
            return todayAt(hour: typical.hour, minute: typical.minute)
                .addingTimeInterval(-buffer)
        }

        // Step 3: Historical average wake time for this weekday
        // Wake times already reflect how early the user needed to be up,
        // so routine + commute are not subtracted again.
        if let avgWake = SleepHistoryStore.shared.averageWakeTime(forWeekday: tomorrowWeekday) {
            return todayAt(hour: avgWake.hour, minute: avgWake.minute)
        }

        // Step 4: 8 AM hard fallback (cold-start, no data yet)
        return todayAt(hour: 8, minute: 0).addingTimeInterval(-buffer)
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
        let commuteMinutes = answers.commute.auto
            ? 30
            : answers.commute.hours * 60 + answers.commute.minutes
        guard commuteMinutes > 0 else { return false }
        let routineMinutes = answers.routine.auto
            ? 60
            : answers.routine.hours * 60 + answers.routine.minutes
        // leaveTime = wakeTime + routineMinutes = arrivalTarget - commuteMinutes
        let leaveTime = calculatedAlarmDate.addingTimeInterval(Double(routineMinutes) * 60)
        let now = Date()
        return now >= calculatedAlarmDate && now < leaveTime
    }

    /// Day name, time string, and AM/PM for the first alarm after the rest period.
    private var nextAlarmInfo: (day: String, time: String, period: String)? {
        let skip = consecutiveRestDaysFromTomorrow
        var check = Calendar.current.date(byAdding: .day, value: skip + 1, to: Date())!
        for _ in 0..<8 {
            if answers.wakeDays.contains(weekdayID(for: check)) {
                // TODO: Replace with calendar-driven resolution for the specific future date.
                // For now uses the 8 AM fallback; full per-day resolution requires
                // fetching events for each candidate date, which is a follow-up task.
                let targetMinutes  = 8 * 60
                let routineMins    = answers.routine.auto ? 60 : answers.routine.hours * 60 + answers.routine.minutes
                let commuteMins: Int = (answers.lifestyle == "student" || answers.lifestyle == "commuter")
                    ? (answers.commute.auto ? 30 : answers.commute.hours * 60 + answers.commute.minutes)
                    : 0
                let wakeMinutes = ((targetMinutes - routineMins - commuteMins) % (24 * 60) + 24 * 60) % (24 * 60)
                let hour        = wakeMinutes / 60
                let minute      = wakeMinutes % 60
                let displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)

                let df = DateFormatter()
                df.dateFormat = "EEEE"
                return (
                    day:    df.string(from: check),
                    time:   String(format: "%d:%02d", displayHour, minute),
                    period: hour >= 12 ? "PM" : "AM"
                )
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

        // answers.sleep.auto == true  →  "let Lunifer learn" → use age baseline
        // answers.sleep.auto == false →  user entered a specific duration → use it
        let sleepHours: Double
        if answers.sleep.auto {
            sleepHours = SleepDurationModel.baselineForAge(answers.age)
        } else {
            sleepHours = Double(answers.sleep.hours) + Double(answers.sleep.minutes) / 60.0
        }

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
            // Load persisted added alarms and prune any whose fire time has passed.
            loadAddedAlarms()
            let now = Date()
            addedAlarms.removeAll { $0.date < now }
            saveAddedAlarms()
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
            // Request alarm authorization — waits for the user to respond
            await LuniferAlarm.shared.requestAuthorization()
            checkAlarmAuthorization()
            // Small delay so the motion permission prompt has time to resolve
            // before we check the result
            try? await Task.sleep(nanoseconds: 500_000_000)
            checkMotionAuthorization()

            // Start commute monitoring on scheduled wake days for commuters/students.
            // CommuteManager will schedule the leave reminder and watch for duration
            // deltas. The arrival target mirrors the hardcoded 8:00 AM used throughout
            // the alarm calculation — swap this for a calendar-driven date when ready.
            if isCommuterUser && answers.wakeDays.contains(weekdayID(for: Date())) {
                var arrComps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                arrComps.hour   = 8
                arrComps.minute = 0
                arrComps.second = 0
                let arrival = Calendar.current.date(from: arrComps) ?? Date()
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            guard !isRunningPreview else { return }
            checkAlarmAuthorization()
            checkMotionAuthorization()
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
            VStack(spacing: 0) {
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
                                .font(.custom("Libre Franklin", size: 63).weight(.light))
                                .foregroundColor(Color.white.opacity(0.95))
                                .monospacedDigit()
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            Text(wakeUpPeriod)
                                .font(.custom("Libre Franklin", size: 60).weight(.light))
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
                                if !overrideActive {
                                    overrideTime = calculatedAlarmDate
                                }
                                overrideActive = true
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

                    // ── Dropdown content ──────────────────────
                    if alarmExpanded {
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
                                    Text("\(snoozeMinutes) min")
                                        .font(.custom("DM Sans", size: 13))
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
                        .padding(.horizontal, 45)
                        .transition(.opacity.combined(with: .offset(y: -8)))
                    }

                }
                .padding(.horizontal, 32)
                .transition(.opacity)
                .onChange(of: overrideTime) { _, newTime in
                    guard overrideActive else { return }
                    overrideTimestamp = newTime.timeIntervalSince1970
                    Task {
                        await LuniferAlarm.shared.scheduleAlarm(for: newTime)
                        await WakeNotification.shared.schedule(wakeDate: newTime, answers: answers)
                    }
                }

                // ── Added Alarm cards ─────────────────────
                if !addedAlarms.isEmpty && !alarmExpanded {
                    VStack(spacing: 0) {
                        Text(addedAlarms.count == 1 ? "ADDED ALARM" : "ADDED ALARMS")
                            .font(.custom("DM Sans", size: 10))
                            .foregroundColor(Color.white.opacity(0.3))
                            .kerning(2.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 60)
                            .padding(.top, 20)
                            .padding(.bottom, 4)

                        ForEach(addedAlarms.sorted { $0.timestamp < $1.timestamp }) { alarm in
                            VStack(spacing: 2) {
                                if !alarm.label.isEmpty {
                                    Text(alarm.label)
                                        .font(.custom("DM Sans", size: 13))
                                        .foregroundColor(Color.white.opacity(0.45))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 60)
                                }

                                HStack(spacing: 0) {
                                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                                        Text(alarm.displayTime)
                                            .font(.custom("Libre Franklin", size: 40).weight(.light))
                                            .foregroundColor(Color.white.opacity(0.80))
                                            .monospacedDigit()
                                        Text(alarm.displayPeriod)
                                            .font(.custom("Libre Franklin", size: 37).weight(.light))
                                            .foregroundColor(Color.white.opacity(0.80))
                                    }
                                    Spacer()
                                    Button {
                                        let id = alarm.id
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            addedAlarms.removeAll { $0.id == id }
                                        }
                                        saveAddedAlarms()
                                        Task { await LuniferAlarm.shared.cancelAddedAlarm(id: id) }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 13, weight: .light))
                                            .foregroundColor(Color.white.opacity(0.4))
                                            .padding(10)
                                            .background(Circle().fill(Color.white.opacity(0.07)))
                                    }
                                }
                                .padding(.horizontal, 60)
                            }
                            .padding(.bottom, 8)
                        }
                    }
                    .offset(y: luniferEnabled ? 0 : 8)
                }

                // ── Commute card ──────────────────────────
                if shouldShowCommuteCard && !alarmExpanded {
                    CommuteStatusCard(answers: answers)
                        .transition(.opacity)
                }

            }
            .opacity(luniferEnabled ? 1 : 0)
            .allowsHitTesting(luniferEnabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(y: -32)
            .sheet(isPresented: $showAddAlarmSheet, onDismiss: {
                withAnimation { addAlarmTapped = false }
            }) {
                AddAlarmSheet(
                    pickerTime: $addedAlarmPickerTime,
                    onSet: { time, label, sound, snooze in
                        let alarm = AddedAlarm(
                            id: UUID(),
                            timestamp: time.timeIntervalSince1970,
                            label: label,
                            sound: sound,
                            snoozeMinutes: snooze
                        )
                        withAnimation(.easeInOut(duration: 0.25)) {
                            addedAlarms.append(alarm)
                        }
                        saveAddedAlarms()
                        showAddAlarmSheet = false
                        Task { await LuniferAlarm.shared.scheduleAddedAlarm(for: time, alarmID: alarm.id) }
                    },
                    onCancel: {
                        showAddAlarmSheet = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color(red: 0.06, green: 0.03, blue: 0.14))
            }

            // ── Unified toggle button — travels from bottom to center ──
            if !alarmExpanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.5)) { luniferEnabled.toggle() }
                    if luniferEnabled { Task { await LuniferAlarm.shared.cancelAlarm() } }
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
        }
        // Dismiss the expanded "Add Alarm" label when the user taps
        // anywhere on the page that isn't the button itself.
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

                if let next = nextAlarmInfo {
                    Text("Next Alarm \(next.day)")
                        .font(.custom("DM Sans", size: 14))
                        .foregroundColor(Color.white.opacity(0.35))
                }
            }
            .padding(.horizontal, 32)
            .offset(y: -32)
        }
    }
}

// ── MARK: Add Alarm Sheet ─────────────────────────────────────

struct AddAlarmSheet: View {
    @Binding var pickerTime: Date
    let onSet:    (Date, String, String, Int) -> Void   // time, label, sound, snoozeMinutes
    let onCancel: () -> Void

    @State private var addedAlarmSound: String = "DeafultAlarm.wav"
    @State private var addedAlarmLabel: String = ""
    @State private var addedAlarmSnoozeMinutes: Int = 5

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

                    Spacer()

                    // ── Set Alarm button ──────────────────────
                    Button {
                        onSet(pickerTime, addedAlarmLabel, addedAlarmSound, addedAlarmSnoozeMinutes)
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


// ── MARK: Commute Status Card ─────────────────────────────────
// Shown on the alarm page after the alarm fires, while the user
// still has time before they need to leave. Displays the survey-
// entered commute duration and the derived leave-by time.
// When live routing is added to CommuteManager, bind this view
// to CommuteManager.shared.currentDurationMinutes instead of
// re-deriving the duration from answers directly.

struct CommuteStatusCard: View {
    let answers: SurveyAnswers

    private var commuteMinutes: Int {
        answers.commute.auto
            ? 30
            : answers.commute.hours * 60 + answers.commute.minutes
    }

    /// leave time = 8:00 AM target − commute duration
    private var leaveTime: Date {
        var comps    = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour   = 8
        comps.minute = 0
        comps.second = 0
        let arrival  = Calendar.current.date(from: comps) ?? Date()
        return arrival.addingTimeInterval(-Double(commuteMinutes) * 60)
    }

    private var leaveTimeString: String {
        let f        = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: leaveTime)
    }

    private var modeIcon: String {
        switch answers.commuteMode {
        case "transit": return "tram.fill"
        case "walk":    return "figure.walk"
        case "bike":    return "bicycle"
        default:        return "car.fill"
        }
    }

    var body: some View {
        VStack(spacing: 8) {

            Text("COMMUTE")
                .font(.custom("DM Sans", size: 10))
                .foregroundColor(Color.white.opacity(0.3))
                .kerning(2.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 60)
                .padding(.top, 20)

            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Image(systemName: modeIcon)
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(Color(red: 0.706, green: 0.588, blue: 0.902))
                        Text("~\(commuteMinutes) min")
                            .font(.custom("Libre Franklin", size: 36).weight(.light))
                            .foregroundColor(Color.white.opacity(0.80))
                            .monospacedDigit()
                    }
                    Text("Leave by \(leaveTimeString)")
                        .font(.custom("DM Sans", size: 13))
                        .foregroundColor(Color.white.opacity(0.40))
                }
                Spacer()
            }
            .padding(.horizontal, 60)
        }
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

