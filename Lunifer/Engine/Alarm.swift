import Foundation
import Combine
import AlarmKit
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// ─────────────────────────────────────────────────────────────
// SECTION 1: ALARM METADATA
// ─────────────────────────────────────────────────────────────
// AlarmKit requires us to attach a "metadata" struct to every alarm.
// Think of metadata as a label we stick on the alarm that tells us
// WHY this alarm was set and what data was used to calculate it.

enum LuniferAlarmMetadataKind {
    static let main = "main"
    static let added = "added"
}

struct LuniferAlarmMetadata: AlarmMetadata {
    var scheduledWakeTime: Date      // The time we calculated the alarm for
    var calendarEventTitle: String   // The name of the first event tomorrow (e.g. "Team standup")
    var routineMinutes: Int          // How long the user's morning routine takes
    var commuteMinutes: Int          // How long their commute takes
    var alarmKind: String
    var addedAlarmID: UUID?

    init(
        scheduledWakeTime: Date,
        calendarEventTitle: String,
        routineMinutes: Int,
        commuteMinutes: Int,
        alarmKind: String = LuniferAlarmMetadataKind.main,
        addedAlarmID: UUID? = nil
    ) {
        self.scheduledWakeTime = scheduledWakeTime
        self.calendarEventTitle = calendarEventTitle
        self.routineMinutes = routineMinutes
        self.commuteMinutes = commuteMinutes
        self.alarmKind = alarmKind
        self.addedAlarmID = addedAlarmID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scheduledWakeTime = try container.decode(Date.self, forKey: .scheduledWakeTime)
        calendarEventTitle = try container.decode(String.self, forKey: .calendarEventTitle)
        routineMinutes = try container.decode(Int.self, forKey: .routineMinutes)
        commuteMinutes = try container.decode(Int.self, forKey: .commuteMinutes)
        alarmKind = try container.decodeIfPresent(String.self, forKey: .alarmKind) ?? LuniferAlarmMetadataKind.main
        addedAlarmID = try container.decodeIfPresent(UUID.self, forKey: .addedAlarmID)
    }

    private enum CodingKeys: String, CodingKey {
        case scheduledWakeTime, calendarEventTitle, routineMinutes, commuteMinutes, alarmKind, addedAlarmID
    }
}

/// Result of the deterministic baseline alarm resolution (before the adaptive
/// bandit offset is applied). Lives here because LuniferAlarm now owns the
/// resolution logic so it can run without any dashboard view on screen — e.g.
/// when self-rescheduling from stopAlarm().
struct BaselineAlarmResolution {
    let alarmDate: Date
    let routineMinutes: Int
    let commuteMinutes: Int
    let firstEvent: CalendarEvent?
}

struct AlarmSchedulingFailure: Equatable {
    let attemptedDate: Date
    let confirmedDate: Date?
}

private let alarmInputTimeoutNanoseconds: UInt64 = 5_000_000_000

enum NextWakeAlarmScheduleResult {
    case scheduled
    case noEligibleWakeDay
    case skipped
    case failed
}

// ─────────────────────────────────────────────────────────────
// SECTION 2: THE MAIN ALARM CLASS
// ─────────────────────────────────────────────────────────────
// This is the main class that controls everything alarm-related.
//
// "@MainActor" means all UI updates happen on the main thread (required for SwiftUI).
// "ObservableObject" means SwiftUI views can watch it and update automatically
//  when something changes (like when an alarm gets scheduled or fires).

@MainActor
class LuniferAlarm: ObservableObject {

    static let shared = LuniferAlarm()
    private let manager = AlarmManager.shared
    private var alarmMutation: Task<Bool, Never>?

    private init() {
        loadAddedAlarmIDs()
    }

     
    @Published var isAuthorized: Bool = false       // Has the user granted alarm permission?
    @Published var activeAlarms: [Alarm] = []       // List of currently scheduled alarms
    @Published var scheduledWakeTime: Date? = nil   // The time the next alarm is set for
    @Published var alertingAlarm: Alarm? = nil      // The alarm currently firing (nil = no alarm ringing)
    @Published var lastSchedulingFailure: AlarmSchedulingFailure? = nil
    @Published private(set) var alarmRegistryUncertain: Bool = false

    /// Snooze duration (minutes) for whichever alarm is currently alerting.
    /// Updated in startMonitoring() when an alarm transitions into the alerting state.
    /// The alarm screen reads this so it always uses the right per-alarm snooze setting.
    @Published var alertingAlarmSnoozeMinutes: Int = 5

    /// Sound filename for whichever alarm is currently alerting.
    /// Updated in startMonitoring() alongside alertingAlarmSnoozeMinutes — added alarms
    /// carry their own sound choice, so the alarm screen must read this rather than the
    /// global selectedAlarmSound AppStorage key.
    @Published var alertingAlarmSound: String = "DeafultAlarm.wav"

    /// True when the user has explicitly denied alarm permission.
    /// Used by the dashboard to drive the "must allow" alert loop.
    var authorizationDenied: Bool {
        #if DEBUG
        if UITestSupport.alarmPermissionDenied { return true }
        #endif
        return manager.authorizationState == .denied
    }

    // ── Sound helper ──────────────────────────────────────────
    // Reads the user's sound picker selection from UserDefaults and
    // returns the bare filename (no extension), which is what
    // AlarmPresentation.Sound.named(_:) expects.
    //
    // Falls back to "DeafultAlarm" if the key is missing (e.g. first
    // launch before the user has visited the sound picker).
    private var selectedAlarmSoundName: String {
        let filename = UserDefaults.standard.string(forKey: "selectedAlarmSound") ?? "DeafultAlarm.wav"
        return (filename as NSString).deletingPathExtension
    }

    // Tracks the first alarm time set each night so adaptive pushes
    // can be capped relative to it. Reset whenever a fresh base alarm is set.
    private var originalScheduledWakeTime: Date? = nil
    private var adaptiveTimer: Timer? = nil

    /// Maximum number of hours the alarm can be pushed later than the original time.
    private let maxAdaptivePushHours: Double = 3.0

    /// Maximum number of hours the alarm can be pulled earlier than the original time.
    /// Prevents Path A from waking the user at an unreasonably early hour just
    /// because they happened to fall asleep very early.
    private let maxAdaptivePullHours: Double = 2.0
    private let minimumScheduleLeadTime: TimeInterval = 60
    private var isLuniferEnabled: Bool {
        UserDefaults.standard.object(forKey: AppPreferencesStore.Keys.luniferEnabled) as? Bool ?? true
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 3: REQUESTING PERMISSION
    // ─────────────────────────────────────────────────────────
    // Before Lunifer can set any alarms, it must ask the user for permission.
    // iOS will show a popup saying "Lunifer wants to schedule alarms" with
    // Allow and Don't Allow buttons.
    // We call this function when the user finishes the survey.
    
    // "async" means this function can wait for things (like the user tapping Allow)
    // without freezing the whole app.

    func requestAuthorization() async {
       
        #if DEBUG
        if UITestSupport.alarmPermissionDenied {
            isAuthorized = false
            return
        }
        #endif
        switch manager.authorizationState {

        case .notDetermined:
            // The user hasn't been asked yet — show the permission popup
            do {
                let state = try await manager.requestAuthorization()
                isAuthorized = state == .authorized
                print(isAuthorized ? "✅ Alarm permission granted" : "❌ Alarm permission denied")
            } catch {
                print("❌ Error requesting alarm permission: \(error.localizedDescription)")
                isAuthorized = false
            }

        case .authorized:
            // Already have permission — nothing to do
            isAuthorized = true

        case .denied:
            // User said no — we can't set alarms
            // In the UI we should show a message directing them to Settings
            isAuthorized = false
            print("❌ Alarm permission denied — tell user to enable in Settings")

        @unknown default:
            // Catch-all for any future permission states Apple might add
            isAuthorized = false
        }
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 4: SCHEDULING THE ALARM
    // ─────────────────────────────────────────────────────────
    // This is the main function that sets the alarm.
    // It gets called every night with the optimal wake time
    // calculated by LuniferEngine/LuniferCalendar.
    //
    // Parameters:
    //   date           — the exact time to fire the alarm
    //   eventTitle     — name of the first calendar event tomorrow
    //   routineMinutes — how long the user's morning routine takes (from survey)
    //   commuteMinutes — how long their commute takes (from survey)

    @discardableResult
    func scheduleAlarm(
        for date: Date,
        eventTitle: String = "your first event",
        routineMinutes: Int = 60,
        commuteMinutes: Int = 30
    ) async -> Bool {
        guard !BackgroundActivitySession.shared.isStopped else { return false }
        guard isSchedulableAlarmDate(date) else {
            print("⚠️ Skipping stale alarm request for \(date.formatted(date: .omitted, time: .shortened))")
            recordSchedulingFailure(attemptedDate: date)
            return false
        }
        let previous = alarmMutation
        let mutation = Task { @MainActor in
            _ = await previous?.value
            guard !BackgroundActivitySession.shared.isStopped else { return false }
            return await self.replaceAlarm(for: date, eventTitle: eventTitle,
                                           routineMinutes: routineMinutes, commuteMinutes: commuteMinutes)
        }
        alarmMutation = mutation
        return await mutation.value
    }

    private func replaceAlarm(for date: Date, eventTitle: String,
                              routineMinutes: Int, commuteMinutes: Int) async -> Bool {
        let generation = BackgroundActivitySession.shared.generation
        guard BackgroundActivitySession.shared.accepts(generation) else { return false }
        guard isSchedulableAlarmDate(date) else {
            recordSchedulingFailure(attemptedDate: date)
            return false
        }
        guard isLuniferEnabled else { return false }
        #if DEBUG
        // Injected failures must not wait for an interactive system permission prompt.
        if UITestSupport.forceScheduleFailure {
            do { try UITestSupport.rejectScheduleIfRequested() }
            catch {
                recordSchedulingFailure(attemptedDate: date)
                return false
            }
        }
        #endif
        // Step 1: Make sure we have permission first
        // If we don't, ask for it. If user still says no, stop here.
        if !isAuthorized || manager.authorizationState != .authorized || authorizationDenied {
            await requestAuthorization()
        }
        guard BackgroundActivitySession.shared.accepts(generation), isAuthorized,
              isLuniferEnabled else { return false }

        // Read the system registry, including alarms recovered after a restart.
        guard let existingAlarms = readAlarmRegistry() else {
            recordSchedulingFailure(attemptedDate: date)
            return false
        }
        let replacedIDs = existingAlarms.filter { !isAddedAlarm($0) }.map(\.id)
        if scheduledWakeTime == nil {
            scheduledWakeTime = existingAlarms.filter { !isAddedAlarm($0) }.compactMap {
                if case .fixed(let date) = $0.schedule, date > Date() { return date }
                return nil
            }.min()
        }

        // Step 3: Design what the alarm looks like when it fires
        // This creates the popup/banner the user sees on their lock screen
        // and in the Dynamic Island when the alarm goes off
        // Note: In iOS 26.1+, AlarmKit uses predefined button constants
        // instead of custom AlarmButton configurations
        let alert = AlarmPresentation.Alert(
            title: "Time to wake up",
            secondaryButton: AlarmButton(
                text: "Snooze",
                textColor: Color(red: 0.75, green: 0.65, blue: 1.0),
                systemImageName: "clock.arrow.circlepath"
            ),
            secondaryButtonBehavior: .countdown
        )

        // Step 4: Bundle the alert design + Lunifer's purple colour into "attributes"
        // AlarmAttributes is AlarmKit's way of packaging everything about
        // how the alarm looks and what data it carries
        let attributes = AlarmAttributes<LuniferAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),  // The alert we designed above
            metadata: LuniferAlarmMetadata(                 // Our custom data attached to this alarm
                scheduledWakeTime: date,
                calendarEventTitle: eventTitle,
                routineMinutes: routineMinutes,
                commuteMinutes: commuteMinutes
            ),
            tintColor: Color(red: 0.55, green: 0.35, blue: 0.95)  // Purple tint for the UI
        )

        // Step 5: Actually schedule the alarm at the exact date/time
        // .fixed(date) means "fire at this exact moment"
        // (as opposed to .relative which fires after a countdown)
        do {
            let alarmID = UUID()
            if !replacedIDs.isEmpty {
                AppPreferencesStore.shared.pendingReplacementAlarmDate = date
            }
            #if DEBUG
            try UITestSupport.rejectScheduleIfRequested()
            #endif
            let _ = try await manager.schedule(
                id: alarmID,            // A unique ID for this alarm — UUID generates a random one
                configuration: .alarm(
                    schedule: .fixed(date),   // Fire at this exact time
                    attributes: attributes,   // Using the design + data we set up above
                    // App Intent the system runs when this alarm is stopped — from
                    // the lock screen, Dynamic Island, or in-app — so the next wake
                    // day is scheduled no matter how the alarm is dismissed.
                    stopIntent: LuniferStopAlarmIntent(alarmID: alarmID.uuidString)
                )
            )

            guard BackgroundActivitySession.shared.accepts(generation) else {
                try? manager.cancel(id: alarmID)
                return false
            }

            // AlarmKit confirmed the replacement. Only now retire the old alarms.
            for oldID in replacedIDs {
                do {
                    try manager.cancel(id: oldID)
                } catch {
                    // Keeping a backup is safer than losing the confirmed replacement.
                    print("❌ Failed to retire previous alarm: \(error.localizedDescription)")
                }
            }
            if let alarms = readAlarmRegistry() {
                activeAlarms = alarms
            }
            originalScheduledWakeTime = nil
            scheduledWakeTime = date
            AppPreferencesStore.shared.clearPendingReplacementAlarm()
            lastSchedulingFailure = nil
            print("✅ Alarm set for \(date.formatted(date: .omitted, time: .shortened))")

            // Log the scheduling event for the ML model
            AlarmBehaviourLogger.shared.logScheduled(for: date)
            return true

        } catch {
            // Something went wrong — print the error for debugging in Xcode console
            print("❌ Failed to schedule alarm: \(error.localizedDescription)")
            AppPreferencesStore.shared.clearPendingReplacementAlarm()
            recordSchedulingFailure(attemptedDate: date)
            return false
        }
    }

    private func recordSchedulingFailure(attemptedDate: Date) {
        lastSchedulingFailure = AlarmSchedulingFailure(
            attemptedDate: attemptedDate,
            confirmedDate: scheduledWakeTime
        )
    }

    private func readAlarmRegistry() -> [Alarm]? {
        do {
            #if DEBUG
            try UITestSupport.rejectAlarmRegistryReadIfRequested()
            #endif
            let alarms = try manager.alarms
            alarmRegistryUncertain = false
            return alarms
        } catch {
            print("❌ Unable to read AlarmKit registry: \(error.localizedDescription)")
            alarmRegistryUncertain = true
            return nil
        }
    }

    private func addedLogicalID(for alarm: Alarm) -> UUID? {
        let records = persistedAddedAlarmRecords()
        if let logicalID = addedAlarmIDs.first(where: { $0.value == alarm.id })?.key {
            if records.contains(where: { $0.id == logicalID }) {
                return logicalID
            }
            addedAlarmIDs.removeValue(forKey: logicalID)
            persistAddedAlarmIDs()
            return nil
        }
        guard case .fixed(let alarmDate) = alarm.schedule else { return nil }
        guard let record = records.first(where: {
            abs($0.date.timeIntervalSince(alarmDate)) < 1
        }) else { return nil }
        addedAlarmIDs[record.id] = alarm.id
        persistAddedAlarmIDs()
        return record.id
    }

    private func isAddedAlarm(_ alarm: Alarm) -> Bool {
        addedLogicalID(for: alarm) != nil
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 4b: ADDED ALARMS
    // ─────────────────────────────────────────────────────────
    // Schedules independently managed alarms set by the user.
    // Each alarm is keyed by a logical UUID (matching AddedAlarm.id)
    // so individual alarms can be cancelled without affecting others.
    // Stored separately from the main Lunifer alarm so cancelling
    // one does not affect the other.

    /// Maps logical AddedAlarm.id → AlarmKit UUID.
    /// Persisted to UserDefaults so the mapping survives app restarts — AlarmKit
    /// assigns its own UUIDs at scheduling time, so this is the only way to
    /// connect a firing AlarmKit alarm back to its Lunifer AddedAlarm record.
    @Published var addedAlarmIDs: [UUID: UUID] = [:]

    private static let addedAlarmIDMapKey = "addedAlarmIDMap"

    /// Loads the persisted logical→AlarmKit UUID map from UserDefaults.
    /// Called at init so the map is ready before startMonitoring() runs.
    private func loadAddedAlarmIDs() {
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.addedAlarmIDMapKey)
                as? [String: String] else { return }
        var restored: [UUID: UUID] = [:]
        for (logicalStr, alarmKitStr) in raw {
            if let logical = UUID(uuidString: logicalStr),
               let alarmKit = UUID(uuidString: alarmKitStr) {
                restored[logical] = alarmKit
            }
        }
        addedAlarmIDs = restored
    }

    /// Writes the current logical→AlarmKit UUID map to UserDefaults.
    /// Called explicitly after every add or remove so the persisted copy stays in sync.
    private func persistAddedAlarmIDs() {
        guard !addedAlarmIDs.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.addedAlarmIDMapKey)
            return
        }
        var raw: [String: String] = [:]
        for (logical, alarmKit) in addedAlarmIDs {
            raw[logical.uuidString] = alarmKit.uuidString
        }
        UserDefaults.standard.set(raw, forKey: Self.addedAlarmIDMapKey)
    }

    func clearAddedAlarmIdentityState() {
        addedAlarmIDs.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.addedAlarmIDMapKey)
    }

    /// Reads the snooze duration for a logical AddedAlarm.id directly from the
    /// persisted addedAlarms JSON in UserDefaults. This avoids maintaining a
    /// redundant in-memory copy — the snooze is already stored on the AddedAlarm
    /// struct itself and written to UserDefaults whenever an alarm is saved.
    private func persistedAddedAlarmRecords() -> [PersistedAddedAlarm] {
        guard let data = UserDefaults.standard.data(forKey: AppPreferencesStore.Keys.addedAlarms),
              let alarms = try? JSONDecoder().decode([PersistedAddedAlarm].self, from: data) else {
            return []
        }
        return alarms
    }

    private func persistedSnoozeMinutes(for logicalID: UUID) -> Int {
        guard let match = persistedAddedAlarmRecords().first(where: { $0.id == logicalID }) else { return 5 }
        return match.snoozeMinutes
    }

    private func persistedSound(for logicalID: UUID) -> String {
        guard let match = persistedAddedAlarmRecords().first(where: { $0.id == logicalID }) else {
            return UserDefaults.standard.string(forKey: "selectedAlarmSound") ?? "DeafultAlarm.wav"
        }
        return match.sound
    }

    /// Returns the repeat days for a logical AddedAlarm from persisted JSON.
    private func persistedRepeatDays(for logicalID: UUID) -> [String] {
        guard let match = persistedAddedAlarmRecords().first(where: { $0.id == logicalID }) else { return [] }
        return match.repeatDays
    }

    /// Removes a single AddedAlarm record from the persisted addedAlarms JSON.
    private func removeAddedAlarmFromStorage(id logicalID: UUID) {
        guard let data = UserDefaults.standard.data(forKey: "addedAlarms"),
              var raw  = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }
        raw.removeAll { ($0["id"] as? String) == logicalID.uuidString }
        if let encoded = try? JSONSerialization.data(withJSONObject: raw) {
            UserDefaults.standard.set(encoded, forKey: "addedAlarms")
        }
    }

    /// Advances a repeating added alarm to its next weekday occurrence and
    /// re-schedules it through AlarmKit. Reads the original time-of-day from
    /// the stored timestamp; searches forward up to 8 days.
    private func rescheduleRepeatingAddedAlarm(logicalID: UUID) {
        guard let data  = UserDefaults.standard.data(forKey: "addedAlarms"),
              var raw   = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let alarms = try? JSONDecoder().decode([PersistedAddedAlarm].self, from: data),
              let match  = alarms.first(where: { $0.id == logicalID }),
              let rawIdx = raw.firstIndex(where: { ($0["id"] as? String) == logicalID.uuidString })
        else { return }

        guard !match.repeatDays.isEmpty else { return }

        let cal       = Calendar.current
        let alarmDate = Date(timeIntervalSince1970: match.timestamp)
        let hour      = cal.component(.hour,   from: alarmDate)
        let minute    = cal.component(.minute, from: alarmDate)
        let idForWD: [Int: String] = [1:"sun",2:"mon",3:"tue",4:"wed",5:"thu",6:"fri",7:"sat"]
        let now       = Date()

        var nextDate: Date? = nil
        for offset in 1...8 {
            guard let day = cal.date(byAdding: .day, value: offset,
                                     to: cal.startOfDay(for: now)) else { continue }
            let wdStr = idForWD[cal.component(.weekday, from: day)] ?? ""
            guard match.repeatDays.contains(wdStr) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour; comps.minute = minute; comps.second = 0
            if let proposed = cal.date(from: comps), proposed > now {
                nextDate = proposed
                break
            }
        }
        guard let nextDate else { return }

        // Patch the stored timestamp in-place so the dashboard row reflects the new time.
        raw[rawIdx]["timestamp"] = nextDate.timeIntervalSince1970
        if let encoded = try? JSONSerialization.data(withJSONObject: raw) {
            UserDefaults.standard.set(encoded, forKey: "addedAlarms")
        }

        // Re-schedule the AlarmKit alarm on the advanced date.
        Task {
            await scheduleAddedAlarm(for: nextDate, alarmID: logicalID,
                                     snoozeMinutes: match.snoozeMinutes)
        }
    }

    func scheduleAddedAlarm(for date: Date, alarmID: UUID, snoozeMinutes: Int) async {
        let generation = BackgroundActivitySession.shared.generation
        guard !BackgroundActivitySession.shared.isStopped else { return }
        if !isAuthorized { await requestAuthorization() }
        guard BackgroundActivitySession.shared.accepts(generation), isAuthorized else { return }

        // Cancel any existing alarm with the same logical ID first
        await cancelAddedAlarm(id: alarmID)

        let alert = AlarmPresentation.Alert(
            title: "Added Alarm",
            secondaryButton: AlarmButton(
                text: "Snooze",
                textColor: Color(red: 0.75, green: 0.65, blue: 1.0),
                systemImageName: "clock.arrow.circlepath"
            ),
            secondaryButtonBehavior: .countdown
        )

        let attributes = AlarmAttributes<LuniferAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: LuniferAlarmMetadata(
                scheduledWakeTime: date,
                calendarEventTitle: "",
                routineMinutes: 0,
                commuteMinutes: 0,
                alarmKind: LuniferAlarmMetadataKind.added,
                addedAlarmID: alarmID
            ),
            tintColor: Color(red: 0.55, green: 0.35, blue: 0.95)
        )

        let alarmKitID = UUID()
        do {
            let _ = try await manager.schedule(
                id: alarmKitID,
                configuration: .alarm(
                    schedule: .fixed(date),
                    attributes: attributes,
                    // Attach a stop intent so one-shot delete and repeating-reschedule
                    // logic runs even when the user dismisses from the lock screen or
                    // Dynamic Island without opening the app.
                    stopIntent: LuniferAddedAlarmStopIntent(logicalAlarmID: alarmID.uuidString)
                )
            )
            guard BackgroundActivitySession.shared.accepts(generation) else {
                try? manager.cancel(id: alarmKitID)
                return
            }
            addedAlarmIDs[alarmID] = alarmKitID
            persistAddedAlarmIDs()
            print("✅ Added alarm set for \(date.formatted(date: .omitted, time: .shortened))")
        } catch {
            print("❌ Failed to schedule added alarm: \(error.localizedDescription)")
        }
    }

    /// Called by `LuniferAddedAlarmStopIntent` when the user dismisses an added
    /// alarm from the lock screen or Dynamic Island. Mirrors the added-alarm branch
    /// of `stopAlarm()` so the same one-shot delete / repeating-reschedule logic
    /// runs regardless of how the alarm was stopped.
    func handleAddedAlarmSystemStop(logicalID: UUID) async {
        let days = persistedRepeatDays(for: logicalID)
        if days.isEmpty {
            // One-shot: remove from storage, clean up the UUID map, refresh dashboard.
            removeAddedAlarmFromStorage(id: logicalID)
            addedAlarmIDs.removeValue(forKey: logicalID)
            persistAddedAlarmIDs()
            NotificationCenter.default.post(name: .luniferAddedAlarmModified, object: nil)
        } else {
            // Repeating: advance to the next qualifying weekday and reschedule.
            rescheduleRepeatingAddedAlarm(logicalID: logicalID)
            NotificationCenter.default.post(name: .luniferAddedAlarmModified, object: nil)
        }
    }

    func cancelAddedAlarm(id: UUID) async {
        let alarmKitID = addedAlarmIDs[id] ?? readAlarmRegistry()?.first { alarm in
            addedLogicalID(for: alarm) == id
        }?.id
        guard let alarmKitID else { return }
        try? manager.cancel(id: alarmKitID)
        addedAlarmIDs.removeValue(forKey: id)
        persistAddedAlarmIDs()
    }

    func cancelAllAddedAlarms() async {
        if let alarms = readAlarmRegistry() {
            for alarm in alarms where isAddedAlarm(alarm) {
                try? manager.cancel(id: alarm.id)
            }
        } else {
            for (_, alarmKitID) in addedAlarmIDs {
                try? manager.cancel(id: alarmKitID)
            }
        }
        addedAlarmIDs.removeAll()
        persistAddedAlarmIDs()
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 4c: ALARM DATE RESOLUTION  (moved from LuniferMain)
    // ─────────────────────────────────────────────────────────
    // Resolves the wake time for a given calendar day via the
    // deterministic 4-step fallback chain, then applies the adaptive
    // bandit offset inside a safety window. Lives on the engine (not
    // the dashboard view) so it can run with no view on screen — e.g.
    // self-rescheduling the next wake day from stopAlarm().

    /// Routine + commute buffer (seconds) for synchronous callers. Reads the
    /// cached live commute duration when auto-commute is on; zero fallback
    /// before a live route exists.
    func routineCommuteBufferSeconds(answers: SurveyAnswers) -> TimeInterval {
        let routine = answers.routine.auto
            ? 60
            : answers.routine.hours * 60 + answers.routine.minutes
        let commute: Int = answers.commute.auto
            ? (CommuteManager.shared.currentDurationMinutes > 0
                ? CommuteManager.commuteMinutesForAlarmMath(CommuteManager.shared.currentDurationMinutes)
                : CommuteManager.surveyDuration(from: answers))
            : CommuteManager.surveyDuration(from: answers)
        return Double(routine + commute) * 60
    }

    /// The next calendar day (start-of-day) after `referenceDay` that is one of
    /// the user's wake days, or nil if none falls within the next 7 days.
    func nextWakeDay(after referenceDay: Date, answers: SurveyAnswers) -> Date? {
        let cal = Calendar.current
        let ids = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        for offset in 1...7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: referenceDay)) else { continue }
            let id = ids[cal.component(.weekday, from: day) - 1]
            if answers.wakeDays.contains(id) { return day }
        }
        return nil
    }

    /// Builds a Date on `day` with the supplied hour/minute.
    private func dateOn(_ day: Date, hour: Int, minute: Int) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return cal.date(from: comps) ?? day
    }

    /// Resolves the deterministic baseline alarm for `targetDay` using the
    /// 4-step fallback chain: live calendar event → historical event pattern →
    /// historical wake median → 8 AM. Async because it may fetch calendar
    /// events and a live commute duration.
    func resolveBaselineAlarmDate(
        answers: SurveyAnswers,
        targetDay: Date,
        inputTimeoutNanoseconds: UInt64 = alarmInputTimeoutNanoseconds
    ) async -> BaselineAlarmResolution {
        let cal = Calendar.current
        let day = cal.startOfDay(for: targetDay)
        let weekday = cal.component(.weekday, from: day)

        let routineMinutes = answers.routine.auto
            ? 60
            : answers.routine.hours * 60 + answers.routine.minutes
        let commuteMinutes: Int
        if answers.hasCommuteSetup {
            if answers.commute.auto {
                let fallback = CommuteManager.surveyDuration(from: answers)
                let live = await Self.withAlarmInputTimeout(
                    nanoseconds: inputTimeoutNanoseconds,
                    fallback: fallback
                ) {
                    await CommuteManager.fetchLiveDuration(answers: answers)
                }
                // Cache so routineCommuteBufferSeconds() and the commute card can
                // read it synchronously for the rest of the session.
                CommuteManager.shared.currentDurationMinutes = live
                commuteMinutes = live
            } else {
                commuteMinutes = answers.commute.hours * 60 + answers.commute.minutes
            }
        } else {
            commuteMinutes = 0
        }
        let buffer = Double(routineMinutes + commuteMinutes) * 60

        // ── Sleep-onset natural wake time ─────────────────────────────────
        // If SleepTracker detected onset tonight, compute when the user will
        // have completed their recommended sleep. This is used in two ways:
        //   • As a lower bound on steps 1–2: wake the user as soon as they've
        //     slept enough rather than holding them until the event deadline.
        //   • As step 3: direct fallback when no calendar/history data exists.
        // Guard: only use an onset from the last 14 hours so we never pull in
        // yesterday's value from a stale retroactive analysis.
        let sleepHours = WearableRecommendationStore.recommendedHours(
            from: WearableRecommendationStore.currentSources(),
            fallback: answers
        )
        let tonightOnset: Date? = {
            guard let onset = SleepTracker.shared.estimatedSleepOnset else { return nil }
            return onset > Date().addingTimeInterval(-14 * 3600) ? onset : nil
        }()
        let naturalWakeTime = Self.sleepBasedWakeTime(
            onset: tonightOnset, sleepHours: sleepHours, targetDay: day, calendar: cal
        )

        // Step 1: Live calendar event on the target day.
        // If sleep onset is known, wake the user at whichever comes first:
        // when they've had enough sleep, or when they must be up for the event.
        await Self.withAlarmInputTimeout(
            nanoseconds: inputTimeoutNanoseconds,
            fallback: ()
        ) {
            await CalendarManager.shared.fetchEvents()
        }
        let firstEvent = CalendarManager.shared.events(for: day)
            .filter { !$0.isAllDay && !$0.isDeclinedByUser }
            .sorted { $0.startDate < $1.startDate }
            .first
        if let event = firstEvent {
            // A real calendar event is driving the alarm — reset the "days since
            // a calendar event was used" counter behind CalendarNudgeNotification.
            CalendarNudgeNotification.shared.recordCalendarEventUsed()
            let eventDeadline = event.startDate.addingTimeInterval(-buffer)
            let alarmDate = naturalWakeTime.map { min($0, eventDeadline) } ?? eventDeadline
            return BaselineAlarmResolution(
                alarmDate: alarmDate,
                routineMinutes: routineMinutes,
                commuteMinutes: commuteMinutes,
                firstEvent: event
            )
        }

        // Step 2: Historical median wake time for this weekday.
        // Wake times already reflect how early the user needed to be up, so
        // routine + commute are not subtracted again.
        // If sleep onset is known, take the earlier of natural wake vs history.
        if let medianWake = SleepHistoryStore.shared.medianWakeTime(forWeekday: weekday) {
            let historyWake = dateOn(day, hour: medianWake.hour, minute: medianWake.minute)
            let alarmDate = naturalWakeTime.map { min($0, historyWake) } ?? historyWake
            return BaselineAlarmResolution(
                alarmDate: alarmDate,
                routineMinutes: routineMinutes,
                commuteMinutes: commuteMinutes,
                firstEvent: nil
            )
        }

        // Step 3: Sleep onset + recommended sleep hours.
        // Fires when no calendar event and no history exist but the user has
        // already fallen asleep tonight. Replaces 8 AM for most real nights.
        if let naturalWake = naturalWakeTime {
            return BaselineAlarmResolution(
                alarmDate: naturalWake,
                routineMinutes: routineMinutes,
                commuteMinutes: commuteMinutes,
                firstEvent: nil
            )
        }

        // Step 4: 8 AM hard fallback — cold-start only, before sleep onset
        // is detected on the very first night with the app installed.
        // Do not subtract commute here because there is no target event yet.
        return BaselineAlarmResolution(
            alarmDate: dateOn(day, hour: 8, minute: 0)
                .addingTimeInterval(-Double(routineMinutes) * 60),
            routineMinutes: routineMinutes,
            commuteMinutes: 0,
            firstEvent: nil
        )
    }

    static func sleepBasedWakeTime(
        onset: Date?, sleepHours: Double, targetDay: Date, calendar: Calendar = .current
    ) -> Date? {
        guard let onset else { return nil }
        let wakeTime = onset.addingTimeInterval(sleepHours * 3600)
        // A recent sleep session must not pull a later wake day's alarm onto today.
        guard calendar.isDate(wakeTime, inSameDayAs: targetDay) else { return nil }
        return wakeTime
    }

    static func withAlarmInputTimeout<T: Sendable>(
        nanoseconds: UInt64,
        fallback: T,
        operation: @Sendable @escaping () async -> T
    ) async -> T {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: nanoseconds)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result ?? fallback
        }
    }

    /// Applies the adaptive bandit offset to a baseline, saves the pending
    /// decision, and returns the final alarm date. Synchronous — the baseline
    /// already carries the event and buffer it needs.
    func decideAlarm(from baseline: BaselineAlarmResolution, answers: SurveyAnswers) -> Date {
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

    /// Convenience: resolve the final adaptive alarm date for a target day.
    /// Used by the dashboard for tomorrow's displayed/scheduled alarm.
    func resolveAlarmDate(answers: SurveyAnswers, targetDay: Date) async -> Date {
        let baseline = await resolveBaselineAlarmDate(answers: answers, targetDay: targetDay)
        return decideAlarm(from: baseline, answers: answers)
    }

    /// Recover the upcoming main alarm across cold launches.
    /// User-added alarms must not prevent the main alarm from being refreshed.
    private func pendingMainAlarmDate() -> Date? {
        let now = Date()
        if let pending = scheduledWakeTime,
           pending > now {
            return pending
        }

        // The in-memory wake time starts empty after a process restart.
        // Read AlarmKit directly rather than waiting for the monitoring task.
        // If that read fails, do not treat cached activeAlarms as confirmed
        // system state; the registry is uncertain until a later read succeeds.
        guard let alarms = readAlarmRegistry() else { return nil }
        let pending = Self.preferredMainAlarmDate(
            from: alarms.compactMap { alarm -> Date? in
                guard !isAddedAlarm(alarm),
                      alarm.state != .alerting,
                      case .fixed(let date) = alarm.schedule,
                      date > now else { return nil }
                return date
            },
            pendingReplacement: AppPreferencesStore.shared.pendingReplacementAlarmDate,
            now: now
        )
        if let pending {
            AppPreferencesStore.shared.clearPendingReplacementAlarm()
            activeAlarms = alarms
            scheduledWakeTime = pending
        }
        return pending
    }

    static func preferredMainAlarmDate(
        from dates: [Date],
        pendingReplacement: Date?,
        now: Date = Date()
    ) -> Date? {
        let futureDates = dates.filter { $0 > now }
        if let pendingReplacement,
           let recoveredReplacement = futureDates.min(by: {
               abs($0.timeIntervalSince(pendingReplacement)) < abs($1.timeIntervalSince(pendingReplacement))
           }),
           abs(recoveredReplacement.timeIntervalSince(pendingReplacement)) < 1 {
            return recoveredReplacement
        }
        return futureDates.min()
    }

    private func pendingMainAlarmToday() -> Date? {
        guard let pending = pendingMainAlarmDate(),
              Calendar.current.isDateInToday(pending) else { return nil }
        return pending
    }

    func hasPendingMainAlarm() -> Bool {
        pendingMainAlarmDate() != nil
    }

    @discardableResult
    private func consumeExpiredMainAlarmIfNeeded(now: Date = Date()) -> Bool {
        guard let scheduledWakeTime,
              scheduledWakeTime <= now else { return false }
        self.scheduledWakeTime = nil
        originalScheduledWakeTime = nil
        AdaptiveAlarmStore.shared.markPendingDecisionIneligible()
        UserDefaults.standard.set(false, forKey: AppPreferencesStore.Keys.overrideActive)
        UserDefaults.standard.removeObject(forKey: AppPreferencesStore.Keys.overrideTimestamp)
        AppPreferencesStore.shared.clearRestDayAlarmOptIn()
        AppPreferencesStore.shared.clearPendingReplacementAlarm()
        AppPreferencesStore.shared.clearFinalizedMainAlarm()
        return true
    }

    /// A rest day must not erase an alarm already set for the next wake day.
    /// Validate the date against current settings so removed days still cancel.
    private func isNextWakeDayAlarm(_ date: Date, answers: SurveyAnswers) -> Bool {
        if AppPreferencesStore.shared.hasRestDayAlarmOptIn(for: date) { return true }
        guard let nextDay = nextWakeDay(after: Date(), answers: answers) else { return false }
        return Calendar.current.isDate(date, inSameDayAs: nextDay)
    }

    func isSchedulableAlarmDate(_ date: Date, now: Date = Date()) -> Bool {
        date.timeIntervalSince(now) >= minimumScheduleLeadTime
    }

    private func nextSchedulableAlarm(
        answers: SurveyAnswers,
        startingWith startDay: Date
    ) async -> (baseline: BaselineAlarmResolution, finalAlarm: Date)? {
        var day = Calendar.current.startOfDay(for: startDay)
        for _ in 0..<8 {
            #if DEBUG
            await UITestSupport.pauseAlarmRefreshIfRequested()
            #endif
            let baseline = await resolveBaselineAlarmDate(answers: answers, targetDay: day)
            let finalAlarm = decideAlarm(from: baseline, answers: answers)
            if isSchedulableAlarmDate(finalAlarm) {
                return (baseline, finalAlarm)
            }
            guard let nextDay = nextWakeDay(after: day, answers: answers) else { return nil }
            day = nextDay
        }
        return nil
    }

    @discardableResult
    func refreshTomorrowAlarm(answers: SurveyAnswers) async -> Date? {
        let defaults = UserDefaults.standard
        guard isLuniferEnabled else { return nil }
        consumeExpiredMainAlarmIfNeeded()

        if AppPreferencesStore.shared.hasPendingStopReschedule {
            switch await scheduleNextWakeAlarm(answers: answers) {
            case .scheduled:
                AppPreferencesStore.shared.clearPendingStopReschedule()
                return scheduledWakeTime
            case .noEligibleWakeDay:
                AppPreferencesStore.shared.clearPendingStopReschedule()
                return nil
            case .skipped, .failed:
                return scheduledWakeTime
            }
        }

        // Opening the app before today's alarm fires must not replace it with
        // tomorrow's alarm, or cancel it because tomorrow is a rest day.
        if let pending = pendingMainAlarmToday() { return pending }

        let calendar = Calendar.current
        if let pending = AppPreferencesStore.shared.pendingRestDayAlarmDate(), calendar.isDateInToday(pending) {
            return pending
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        let weekdayIDs = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        let tomorrowID = weekdayIDs[calendar.component(.weekday, from: tomorrow) - 1]
        if !answers.wakeDays.contains(tomorrowID),
           !AppPreferencesStore.shared.hasRestDayAlarmOptIn(for: tomorrow) {
            if let pending = pendingMainAlarmDate(), isNextWakeDayAlarm(pending, answers: answers) {
                return pending
            }
            switch await scheduleNextWakeAlarm(answers: answers) {
            case .scheduled:
                return scheduledWakeTime
            case .noEligibleWakeDay:
                AdaptiveAlarmStore.shared.clearPendingDecision()
                await cancelAlarm()
                WakeNotification.shared.cancel()
                return nil
            case .skipped, .failed:
                return scheduledWakeTime
            }
        }

        // A manual override applies only while tomorrow remains a selected wake
        // day. Check the wake-day cancellation above before respecting it so a
        // settings change cannot leave an overridden AlarmKit alarm registered.
        guard !defaults.bool(forKey: AppPreferencesStore.Keys.overrideActive) else { return nil }

        let previousDecision = AdaptiveAlarmStore.shared.pendingDecision()
        guard let candidate = await nextSchedulableAlarm(answers: answers, startingWith: tomorrow) else {
            restorePendingDecision(previousDecision)
            return scheduledWakeTime
        }
        guard isLuniferEnabled else {
            restorePendingDecision(previousDecision)
            return nil
        }
        let baseline = candidate.baseline
        let finalAlarm = candidate.finalAlarm
        guard await scheduleAlarm(for: finalAlarm, eventTitle: baseline.firstEvent?.title ?? "your first event", routineMinutes: baseline.routineMinutes, commuteMinutes: baseline.commuteMinutes) else {
            restorePendingDecision(previousDecision)
            return scheduledWakeTime
        }
        guard isLuniferEnabled else { return nil }
        await WakeNotification.shared.schedule(wakeDate: finalAlarm, answers: answers)
        return finalAlarm
    }

    private func restorePendingDecision(_ decision: AdaptiveAlarmDecision?) {
        if let decision {
            AdaptiveAlarmStore.shared.savePendingDecision(decision)
        } else {
            AdaptiveAlarmStore.shared.clearPendingDecision()
        }
    }

    /// Schedules the next wake day's alarm so Lunifer keeps running without the
    /// user reopening the app. No-op when Lunifer is disabled or no upcoming
    /// wake day exists. Called when re-enabling Lunifer and after dismissing the main alarm.
    @discardableResult
    func scheduleNextWakeAlarm(answers: SurveyAnswers) async -> NextWakeAlarmScheduleResult {
        guard isLuniferEnabled else { return .skipped }
        guard let nextDay = nextWakeDay(after: Date(), answers: answers) else { return .noEligibleWakeDay }

        let previousDecision = AdaptiveAlarmStore.shared.pendingDecision()
        guard let candidate = await nextSchedulableAlarm(answers: answers, startingWith: nextDay) else {
            restorePendingDecision(previousDecision)
            return .failed
        }
        guard isLuniferEnabled else {
            restorePendingDecision(previousDecision)
            return .skipped
        }
        let baseline = candidate.baseline
        let finalAlarm = candidate.finalAlarm

        guard await scheduleAlarm(
            for: finalAlarm,
            eventTitle: baseline.firstEvent?.title ?? "your first event",
            routineMinutes: baseline.routineMinutes,
            commuteMinutes: baseline.commuteMinutes
        ) else {
            restorePendingDecision(previousDecision)
            return .failed
        }

        guard isLuniferEnabled else { return .skipped }
        // Keep the wake-reminder chain alive for the newly scheduled day.
        await WakeNotification.shared.schedule(wakeDate: finalAlarm, answers: answers)
        return .scheduled
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 5: CANCELLING THE ALARM
    // ─────────────────────────────────────────────────────────
    // Cancels the main Lunifer alarm when the user disables Lunifer
    // or the selected wake days no longer permit it. Replacement scheduling
    // retires old alarms only after the new alarm is confirmed.
    //
    // IMPORTANT: This must NOT touch user-added alarms. activeAlarms
    // mirrors every AlarmKit alarm scheduled by this app, including the
    // ones the user added manually from the dashboard. Skipping any ID
    // present in addedAlarmIDs.values keeps those alarms intact across
    // every main-alarm reschedule. Without this filter, opening the
    // dashboard, adapting the alarm, or toggling Lunifer would silently
    // wipe every added alarm out of AlarmKit while leaving orphan cards
    // visible on the dashboard.

    func cancelAlarm() async {
        let previous = alarmMutation
        let mutation = Task { @MainActor in
            _ = await previous?.value
            guard let alarms = self.readAlarmRegistry() else {
                return false
            }
            for alarm in alarms where !self.isAddedAlarm(alarm) {
                do {
                    try self.manager.cancel(id: alarm.id)
                } catch {
                    print("❌ Failed to cancel alarm: \(error.localizedDescription)")
                }
            }
            if let alarms = self.readAlarmRegistry() {
                self.activeAlarms = alarms
            }
            self.scheduledWakeTime = nil
            return true
        }
        alarmMutation = mutation
        _ = await mutation.value
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 6: MONITORING ALARM STATE
    // ─────────────────────────────────────────────────────────
    // This function runs continuously in the background from the moment
    // the app opens. It listens for any changes to our alarms —
    // like when a new one is scheduled, cancelled, or fires.
    //
    // "for await" means: keep looping every time AlarmKit sends us an update.
    // It's like subscribing to a live news feed.
    //
    // Add this to ContentView.swift:
    // .task { await LuniferAlarm.shared.startMonitoring() }

    private var monitoringTask: Task<Void, Never>?

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        alertingAlarm = nil
    }

    func startMonitoring() async {
        guard monitoringTask == nil else { return }
        let task = Task { @MainActor in await self.observeAlarmUpdates() }
        monitoringTask = task
        await task.value
    }

    private func observeAlarmUpdates() async {
        for await alarms in manager.alarmUpdates {
            guard !Task.isCancelled else { return }
            guard !BackgroundActivitySession.shared.isStopped else { continue }

            // Update our local list of active alarms so the UI stays in sync
            activeAlarms = alarms

            // Check if any alarm is currently firing
            let firing = alarms.first(where: { if case .alerting = $0.state { return true }; return false })

            if let firing {
                // Only log and resolve snooze when the alarm first starts firing, not on every update
                if alertingAlarm == nil {
                    AlarmBehaviourLogger.shared.logAlarmFired(at: Date())
                    let firedStr: String = {
                        let f = DateFormatter(); f.dateFormat = "h:mm a"
                        return f.string(from: Date())
                    }()
                    DebugAlarmEventStore.shared.log(type: "fired", detail: "at \(firedStr)")

                    // Resolve the snooze duration and sound for this specific alarm.
                    // If the firing AlarmKit ID maps to a logical added-alarm ID, use
                    // that alarm's stored snooze and sound. Otherwise fall back to the
                    // main alarm's dedicated UserDefaults keys.
                    if let logicalID = addedLogicalID(for: firing) {
                        alertingAlarmSnoozeMinutes = persistedSnoozeMinutes(for: logicalID)
                        alertingAlarmSound = persistedSound(for: logicalID)
                    } else {
                        let stored = UserDefaults.standard.integer(forKey: "mainAlarmSnoozeMinutes")
                        alertingAlarmSnoozeMinutes = stored > 0 ? stored : 5
                        alertingAlarmSound = UserDefaults.standard.string(forKey: "selectedAlarmSound") ?? "DeafultAlarm.wav"
                    }
                }
                alertingAlarm = firing
            } else {
                alertingAlarm = nil
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 7: SNOOZE
    // ─────────────────────────────────────────────────────────
    // Dismisses the current alarm and reschedules it for now + snoozeMinutes.

    func snooze(minutes: Int) async {
        guard let alarm = alertingAlarm else { return }
        let snoozeDate = Date().addingTimeInterval(Double(minutes) * 60)
        let snoozeStr: String = {
            let f = DateFormatter(); f.dateFormat = "h:mm a"
            return f.string(from: snoozeDate)
        }()
        DebugAlarmEventStore.shared.log(type: "snoozed", detail: "+\(minutes) min → \(snoozeStr)")

        // If the firing alarm is a user-added alarm, re-schedule it through the
        // added-alarm path so it keeps its logical UUID and stays separate from
        // the main Lunifer alarm. Otherwise use the main alarm path.
        if let logicalID = addedLogicalID(for: alarm) {
            try? manager.cancel(id: alarm.id)
            alertingAlarm = nil
            await scheduleAddedAlarm(for: snoozeDate, alarmID: logicalID, snoozeMinutes: minutes)
        } else {
            AdaptiveAlarmStore.shared.markPendingDecisionIneligible()
            try? manager.cancel(id: alarm.id)
            alertingAlarm = nil
            await scheduleAlarm(for: snoozeDate)
        }
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 8: STOP ALARM
    // ─────────────────────────────────────────────────────────
    // Dismisses the currently firing alarm and logs the dismiss event.

    func stopAlarm() async {
        var wasMainAlarm = false
        if let alarm = alertingAlarm {
            // Check whether this is a user-added alarm and handle repeat/delete logic.
            if let logicalID = addedLogicalID(for: alarm) {
                let days = persistedRepeatDays(for: logicalID)
                if days.isEmpty {
                    // One-shot alarm: remove from storage, mapping, and notify dashboard.
                    removeAddedAlarmFromStorage(id: logicalID)
                    addedAlarmIDs.removeValue(forKey: logicalID)
                    persistAddedAlarmIDs()
                    NotificationCenter.default.post(name: .luniferAddedAlarmModified, object: nil)
                } else {
                    // Repeating alarm: advance to next qualifying weekday.
                    rescheduleRepeatingAddedAlarm(logicalID: logicalID)
                    NotificationCenter.default.post(name: .luniferAddedAlarmModified, object: nil)
                }
            } else {
                // No logical mapping → this is the main Lunifer alarm.
                wasMainAlarm = true
            }
            try? manager.cancel(id: alarm.id)
        }
        AlarmBehaviourLogger.shared.logDismiss(at: Date())
        DebugAlarmEventStore.shared.log(type: "dismissed")
        alertingAlarm = nil
        scheduledWakeTime = nil

        // ── Self-perpetuation ────────────────────────────────────
        // Once the main alarm is dismissed, immediately schedule the next wake
        // day so Lunifer keeps running without the user reopening the app. The
        // logDismiss() above already consumed the fired decision's outcome, so
        // scheduleNextWakeAlarm() safely creates a fresh pending decision.
        if wasMainAlarm {
            AppPreferencesStore.shared.markPendingStopReschedule()
            // The manual override only applied to the alarm that just fired.
            UserDefaults.standard.set(false, forKey: "overrideActive")
            UserDefaults.standard.removeObject(forKey: "overrideTimestamp")
            // A rest-day opt-in (if any) has now been consumed by this firing.
            AppPreferencesStore.shared.clearRestDayAlarmOptIn()
            if let answers = SurveyAnswers.loadFromDefaults() {
                switch await scheduleNextWakeAlarm(answers: answers) {
                case .scheduled, .noEligibleWakeDay:
                    AppPreferencesStore.shared.clearPendingStopReschedule()
                case .skipped, .failed:
                    break
                }
            }
        }
    }

    /// Runs after the main alarm is stopped via the system alert UI (lock screen
    /// or Dynamic Island), invoked by `LuniferStopAlarmIntent`. The system has
    /// already stopped the alarm, so this records the dismissal and schedules the
    /// next wake day — the same tail as the in-app Stop path in `stopAlarm()`.
    /// This is what keeps the alarm chain running when the user never opens the app.
    func rescheduleAfterSystemStop() async {
        AlarmBehaviourLogger.shared.logDismiss(at: Date())
        DebugAlarmEventStore.shared.log(type: "dismissed")
        alertingAlarm = nil
        scheduledWakeTime = nil
        AppPreferencesStore.shared.markPendingStopReschedule()
        // The manual override only applied to the alarm that just fired.
        UserDefaults.standard.set(false, forKey: "overrideActive")
        UserDefaults.standard.removeObject(forKey: "overrideTimestamp")
        // A rest-day opt-in (if any) has now been consumed by this firing.
        AppPreferencesStore.shared.clearRestDayAlarmOptIn()
        if let answers = SurveyAnswers.loadFromDefaults() {
            switch await scheduleNextWakeAlarm(answers: answers) {
            case .scheduled, .noEligibleWakeDay:
                AppPreferencesStore.shared.clearPendingStopReschedule()
            case .skipped, .failed:
                break
            }
        }
    }

    func recordWokeBeforeAlarmIfNeeded(at wakeDate: Date) {
        guard let scheduledWakeTime else { return }
        let leadSeconds = scheduledWakeTime.timeIntervalSince(wakeDate)
        guard leadSeconds > 5 * 60, leadSeconds <= 2 * 3600 else { return }

        AlarmBehaviourLogger.shared.logWokeBeforeAlarm(at: wakeDate)
        DebugAlarmEventStore.shared.log(type: "woke_before")
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 9: ADAPTIVE RESCHEDULING
    // ─────────────────────────────────────────────────────────
    // If the sleep tracker detects the user is still awake after
    // their recommended bedtime, the alarm is pushed forward to
    // preserve their full sleep duration from the current moment.
    //
    // ALGORITHM (runs every 5 minutes):
    //   • User is NOT asleep
    //   • Current time is past bedtime (alarm − sleepDuration)
    //   • There is a scheduled alarm
    //   → newWakeTime = now + sleepDuration
    //   → if newWakeTime > currentAlarm → reschedule
    //
    // CAP: The alarm will not be pushed more than 3 hours past the
    // original scheduled time so it doesn't drift indefinitely.

    /// Starts the adaptive timer. Call this from the dashboard on load.
    func startAdaptiveRescheduling() {
        guard !BackgroundActivitySession.shared.isStopped else { return }
        adaptiveTimer?.invalidate()
        adaptiveTimer = Timer.scheduledTimer(
            withTimeInterval: 5 * 60,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkAndAdaptAlarm()
            }
        }
    }

    func stopAdaptiveRescheduling() {
        adaptiveTimer?.invalidate()
        adaptiveTimer = nil
    }

    /// Runs an immediate adaptive check against the current calendar.
    /// Call this when the app returns to the foreground so that a calendar
    /// event added while the app was suspended is caught promptly rather
    /// than waiting up to 5 minutes for the next timer tick.
    func checkAlarmAgainstCalendar() async {
        await checkAndAdaptAlarm()
    }

    private func checkAndAdaptAlarm() async {
        // Only run while Lunifer is enabled
        guard isLuniferEnabled else { return }

        // Automatic checks leave today's upcoming alarm unchanged until it fires.
        guard pendingMainAlarmToday() == nil else { return }

        // If the user has manually overridden the alarm, respect that choice and
        // make no further changes until the override clears after the alarm passes.
        guard !UserDefaults.standard.bool(forKey: "overrideActive") else {
            print("⏸️ Adaptive rescheduling paused — manual override is active")
            return
        }

        // Need a scheduled alarm to adjust
        guard let currentAlarm = scheduledWakeTime else { return }

        // ── Guard: don't adapt (or schedule) on rest days ───
        // If tomorrow isn't a wake day, cancel any lingering alarm and bail.
        // This handles the case where wake-day settings changed after the
        // alarm was already registered with AlarmKit.
        let surveyAnswers = SurveyAnswers.loadFromDefaults()
        let wakeDays = surveyAnswers?.wakeDays ?? ["mon", "tue", "wed", "thu", "fri"]
        let cal2 = Calendar.current
        let tomorrow2 = cal2.date(byAdding: .day, value: 1, to: cal2.startOfDay(for: Date())) ?? Date()
        let tomorrowWeekdayIndex = cal2.component(.weekday, from: tomorrow2) - 1
        let weekdayIDs = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        let tomorrowID = weekdayIDs[tomorrowWeekdayIndex]
        // Skip the rest-day cancel when the user explicitly opted into an alarm via
        // the rest-day notification: either it's for tomorrow, or it's a still-pending
        // alarm scheduled for today (relaunch in the pre-dawn hours of the rest day,
        // after "tomorrow" has rolled past the alarm's own day).
        let hasPendingTodayOptIn = AppPreferencesStore.shared.pendingRestDayAlarmDate()
            .map { Calendar.current.isDateInToday($0) } ?? false
        guard wakeDays.contains(tomorrowID)
            || AppPreferencesStore.shared.hasRestDayAlarmOptIn(for: tomorrow2)
            || hasPendingTodayOptIn else {
            if let answers = surveyAnswers,
               let pending = pendingMainAlarmDate(),
               isNextWakeDayAlarm(pending, answers: answers) {
                return
            }
            await cancelAlarm()
            return
        }

        // ── Derive sleep duration from wearable data or saved survey answers ──
        let answers = surveyAnswers
        let sleepHours: Double
        if let a = answers {
            sleepHours = WearableRecommendationStore.recommendedHours(
                from: WearableRecommendationStore.currentSources(),
                fallback: a
            )
        } else {
            sleepHours = 8.0
        }

        let now = Date()
        let expectedBedtime = currentAlarm.addingTimeInterval(-sleepHours * 3600)

        // ── Derive routine & commute for calendar constraint ─
        let routineMins: Int
        let commuteMins: Int
        if let a = answers {
            routineMins = a.routine.auto
                ? 60
                : a.routine.hours * 60 + a.routine.minutes
            if a.hasCommuteSetup {
                if a.commute.auto {
                    // Prefer the live GPS-routed duration cached by CommuteManager;
                    // fall back to zero until a live route exists.
                    let live = CommuteManager.shared.currentDurationMinutes
                    commuteMins = live > 0 ? CommuteManager.commuteMinutesForAlarmMath(live) : CommuteManager.surveyDuration(from: a)
                } else {
                    commuteMins = CommuteManager.surveyDuration(from: a)
                }
            } else {
                commuteMins = 0
            }
        } else {
            routineMins = 60
            // Same live-first logic when answers aren't available.
            let live = CommuteManager.shared.currentDurationMinutes
            commuteMins = live > 0 ? CommuteManager.commuteMinutesForAlarmMath(live) : 0
        }

        let calendarFinalized = AppPreferencesStore.shared.isMainAlarmFinalized(for: currentAlarm)

        let latestAllowedAlarm: Date?
        if calendarFinalized {
            latestAllowedAlarm = nil
        } else {
            // ── Calendar constraint ──────────────────────────────
            // If the user has a timed event tomorrow, calculate the
            // latest alarm that still lets them complete their morning
            // routine and commute before the event starts.
            await CalendarManager.shared.fetchEvents()
            guard isLuniferEnabled else { return }
            if let firstEvent = CalendarManager.shared.firstEventTomorrow {
                let bufferSeconds = Double(routineMins + commuteMins) * 60
                latestAllowedAlarm = firstEvent.startDate.addingTimeInterval(-bufferSeconds)
            } else {
                latestAllowedAlarm = nil
            }
        }

        // Helper: clamp a proposed alarm so it respects both the
        // 3-hour adaptive cap AND the calendar constraint.
        func clamped(_ proposed: Date) -> Date {
            var result = proposed
            if let original = originalScheduledWakeTime {
                // Don't push more than 3 hours later than the original alarm
                let cap = original.addingTimeInterval(maxAdaptivePushHours * 3600)
                result = min(result, cap)
                // Don't pull more than 2 hours earlier than the original alarm.
                // Prevents an unusually early sleep onset from producing an
                // alarm time that would feel jarring (e.g. 4 AM).
                let floor = original.addingTimeInterval(-maxAdaptivePullHours * 3600)
                result = max(result, floor)
            }
            // Don't push past the point where routine + commute
            // would cause the user to miss their first event
            if let latest = latestAllowedAlarm {
                result = min(result, latest)
            }
            return result
        }

        // ── Path C: calendar pull-forward ────────────────────────────
        // A morning event was added (or moved earlier) after the alarm was
        // set. If the current alarm is already later than the event deadline,
        // reschedule immediately — no sleep state required. This handles the
        // case where resolveAlarmDate() ran hours ago (e.g. at 10am) and a
        // new early meeting was added to the calendar that afternoon.
        if let latest = latestAllowedAlarm,
           currentAlarm > latest,
           currentAlarm.timeIntervalSince(latest) >= 2 * 60 {
            let fmt = DateFormatter()
            fmt.dateFormat = "h:mm a"
            print("📅 Calendar pull: \(fmt.string(from: currentAlarm)) → \(fmt.string(from: latest))")
            guard await scheduleAlarm(for: latest) else { return }
            guard isLuniferEnabled else { return }
            AdaptiveAlarmStore.shared.updatePendingFinalAlarm(to: latest)
            return
        }

        // ── UNIFIED SLEEP-ONSET MECHANISM ───────────────────
        // Replaces the old two-path (A/B) logic with a single rule:
        //
        //   proposedWakeTime = (estimatedSleepOnset ?? now) + sleepHours
        //
        // Before sleep onset is known, `now` acts as a running proxy so
        // the alarm is always pushed far enough ahead if the user is still
        // awake past bedtime. Once onset is detected by the sleep tracker,
        // the calculation anchors to the actual onset time instead, giving
        // the same precision as the old Path A without needing a separate
        // branch or a one-shot flag.
        //
        // The guard below means nothing happens before bedtime — the
        // proposed time is already earlier than the current alarm so the
        // minimum-change threshold filters it out automatically.

        // Only act after bedtime has passed — no point adjusting early.
        guard now > expectedBedtime else { return }

        // Use actual sleep onset when available; fall back to now as a proxy.
        let referenceTime = SleepTracker.shared.estimatedSleepOnset ?? now
        let proposed = referenceTime.addingTimeInterval(sleepHours * 3600)

        // Snapshot the original alarm on the first adjustment of the night.
        if originalScheduledWakeTime == nil {
            originalScheduledWakeTime = currentAlarm
        }

        let adjusted = clamped(proposed)

        // Skip if the change is less than 2 minutes — avoids micro-reschedules
        // on repeated timer ticks once the alarm has already settled.
        guard abs(adjusted.timeIntervalSince(currentAlarm)) >= 2 * 60 else { return }

        let newTime = adjusted

        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        let arrow = newTime > currentAlarm ? "→" : "←"
        print("⏰ Adaptive: \(fmt.string(from: currentAlarm)) \(arrow) \(fmt.string(from: newTime))")

        // Preserve originalScheduledWakeTime across the internal reschedule —
        // scheduleAlarm() resets it, so save and restore it.
        let savedOriginal = originalScheduledWakeTime!
        guard await scheduleAlarm(for: newTime) else { return }
        guard isLuniferEnabled else { return }
        AdaptiveAlarmStore.shared.updatePendingFinalAlarm(to: newTime)
        originalScheduledWakeTime = savedOriginal
    }
}

// ─────────────────────────────────────────────────────────────
// SECTION 7: BEHAVIOUR LOGGER
// ─────────────────────────────────────────────────────────────
// Records inferences about the user's alarm behaviour and saves
// a single document to Firestore per morning session.
//
// The primary signals logged are:
//   - Whether the user dismissed the alarm normally
//   - Whether the user woke before the alarm (alarm was too late)
//
// Snooze count is intentionally NOT recorded — it is not used
// in the sleep duration recommendation algorithm.
//
// Over time this gives the model a clean signal to personalise
// future alarm times by day of week and sleep pattern.

class AlarmBehaviourLogger {

    static let shared = AlarmBehaviourLogger()

    // ── Session state ─────────────────────────────────────────

    private var scheduledWakeTime: Date? = nil
    private var alarmFiredAt: Date?      = nil

    // ── Lifecycle hooks ───────────────────────────────────────

    /// Called when a new alarm is scheduled for the night.
    func logScheduled(for date: Date) {
        scheduledWakeTime = date
        alarmFiredAt      = nil
        print("📅 Alarm scheduled for \(date.formatted(date: .omitted, time: .shortened))")
    }

    /// Called when the alarm fires. Starts a new session.
    func logAlarmFired(at date: Date) {
        alarmFiredAt = date
        print("🔔 Alarm fired at \(date.formatted(date: .omitted, time: .shortened))")
    }

    /// Called when the user taps Dismiss. Finalises the session
    /// and saves the inference to Firestore.
    func logDismiss(at date: Date) {
        saveInference(outcome: "dismissed", at: date)
        resetSession()
    }

    /// Called when the user woke before the alarm fired.
    /// (Used when HealthKit / SleepTracker integration surfaces this signal.)
    func logWokeBeforeAlarm(at date: Date) {
        guard scheduledWakeTime != nil else { return }
        saveInference(outcome: "woke_before_alarm", at: date)
        resetSession()
    }

    // ── Inference logic ───────────────────────────────────────

    /// Saves a single inference document to Firestore for the morning session.
    private func saveInference(outcome: String, at date: Date) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Assessment based on wake outcome only — snooze frequency is not used.
        let assessment: String = (outcome == "woke_before_alarm") ? "too_late" : "on_time"

        var inference: [String: Any] = [
            "date":       date,
            "dayOfWeek":  Calendar.current.component(.weekday, from: date),
            "outcome":    outcome,
            "assessment": assessment
        ]
        if let scheduled = scheduledWakeTime { inference["scheduledWakeTime"] = scheduled }
        if let fired     = alarmFiredAt      { inference["alarmFiredAt"]      = fired     }

        if let adaptiveOutcome = AdaptiveAlarmStore.shared.recordOutcome(
            outcome: outcome,
            observedAt: date,
            scheduledWakeTime: scheduledWakeTime,
            alarmFiredAt: alarmFiredAt
        ) {
            inference["adaptiveDecisionID"] = adaptiveOutcome.decisionID.uuidString
            inference["adaptiveOffsetMinutes"] = adaptiveOutcome.selectedOffsetMinutes
            inference["adaptiveReward"] = adaptiveOutcome.reward
            inference["adaptiveRecommendedSleepHours"] = adaptiveOutcome.recommendedSleepHours
            if let actualSleepHours = adaptiveOutcome.actualSleepHours {
                inference["adaptiveActualSleepHours"] = actualSleepHours
            }
        }

        Firestore.firestore()
            .collection("users").document(uid)
            .collection("alarmInferences")
            .addDocument(data: inference) { error in
                if let error {
                    print("❌ Failed to save alarm inference: \(error.localizedDescription)")
                } else {
                    print("✅ Alarm inference saved — assessment: \(assessment)")
                }
            }
    }

    private func resetSession() {
        scheduledWakeTime = nil
        alarmFiredAt      = nil
    }
}

// ─────────────────────────────────────────────────────────────
// PersistedAddedAlarm
// ─────────────────────────────────────────────────────────────
// Minimal Codable projection of AddedAlarm used by LuniferAlarm
// to read snooze preferences from the already-persisted addedAlarms
// JSON without importing the full view-layer model.
// JSONDecoder ignores unrecognised keys, so this decodes cleanly
// alongside any other fields stored on AddedAlarm.

private struct PersistedAddedAlarm: Codable {
    let id: UUID
    let timestamp: Double
    let label: String
    let snoozeMinutes: Int
    let sound: String
    let repeatDays: [String]
    var date: Date { Date(timeIntervalSince1970: timestamp) }

    // Backward-compatible — old JSON has no repeatDays key.
    init(from decoder: Decoder) throws {
        let c          = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self,   forKey: .id)
        timestamp      = try c.decode(Double.self, forKey: .timestamp)
        label          = try c.decode(String.self, forKey: .label)
        snoozeMinutes  = try c.decode(Int.self,    forKey: .snoozeMinutes)
        sound          = try c.decode(String.self, forKey: .sound)
        repeatDays     = (try? c.decode([String].self, forKey: .repeatDays)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, label, snoozeMinutes, sound, repeatDays
    }
}

// ─────────────────────────────────────────────────────────────
// Notification posted by stopAlarm() so the dashboard reloads
// whenever a one-shot alarm is deleted or a repeating one advances.

extension Notification.Name {
    static let luniferAddedAlarmModified = Notification.Name("luniferAddedAlarmModified")
}

// ─────────────────────────────────────────────────────────────
// DebugAlarmEventStore
// ─────────────────────────────────────────────────────────────
// Lightweight log of alarm lifecycle events for the debug panel.
// Keeps the last 30 events in UserDefaults across app launches.
// Entirely separate from AdaptiveAlarmStore — debug logging
// never touches the training pipeline.

struct DebugAlarmEvent: Codable, Identifiable {
    let id: UUID
    let type: String     // "fired" | "snoozed" | "dismissed" | "woke_before"
    let timestamp: Date
    let detail: String?  // e.g. "+5 min → 7:23 AM"
}

final class DebugAlarmEventStore {
    static let shared = DebugAlarmEventStore()
    private let key = "luniferDebugAlarmEvents"
    private let maxEvents = 30
    private init() {}

    func log(type: String, detail: String? = nil, at date: Date = Date()) {
        var events = load()
        events.append(DebugAlarmEvent(id: UUID(), type: type, timestamp: date, detail: detail))
        if events.count > maxEvents { events = Array(events.suffix(maxEvents)) }
        save(events)
    }

    func load() -> [DebugAlarmEvent] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let events = try? JSONDecoder().decode([DebugAlarmEvent].self, from: data)
        else { return [] }
        return events
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func save(_ events: [DebugAlarmEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
