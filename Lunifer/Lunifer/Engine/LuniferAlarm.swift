import Foundation
import AlarmKit
import SwiftUI

// ── MARK: LuniferAlarmMetadata ────────────────────────────────
// Required by AlarmKit — carries custom data with each alarm.
// nonisolated required in Xcode 26 where types are MainActor-isolated by default.

nonisolated struct LuniferAlarmMetadata: AlarmMetadata {
    var scheduledWakeTime: Date
    var calendarEventTitle: String
    var routineMinutes: Int
    var commuteMinutes: Int
}

// ── MARK: LuniferAlarm ────────────────────────────────────────
// Handles all alarm scheduling, snoozing, cancelling, and
// behaviour logging for the ML model.
// Requires iOS 26+ and NSAlarmKitUsageDescription in Info.plist.

@MainActor
class LuniferAlarm: ObservableObject {

    static let shared = LuniferAlarm()

    private let manager = AlarmManager.shared

    // ── Published state ──
    @Published var isAuthorized: Bool = false
    @Published var activeAlarms: [Alarm] = []
    @Published var scheduledWakeTime: Date? = nil

    // ── MARK: Request Authorization ───────────────────────────
    // Call this when the user completes the survey.
    // Shows a system prompt explaining why Lunifer needs alarm access.
    func requestAuthorization() async {
        switch manager.authorizationState {
        case .notDetermined:
            do {
                let state = try await manager.requestAuthorization()
                isAuthorized = state == .authorized
                print(isAuthorized ? "✅ AlarmKit authorized" : "❌ AlarmKit denied")
            } catch {
                print("❌ AlarmKit authorization error: \(error.localizedDescription)")
                isAuthorized = false
            }
        case .authorized:
            isAuthorized = true
        case .denied:
            isAuthorized = false
            print("❌ AlarmKit denied — direct user to Settings")
        @unknown default:
            isAuthorized = false
        }
    }

    // ── MARK: Schedule Alarm ──────────────────────────────────
    // Call this every night with the optimal wake time calculated
    // by LuniferCalendar.calculateAlarmTime()
    func scheduleAlarm(
        for date: Date,
        eventTitle: String = "your first event",
        routineMinutes: Int = 60,
        commuteMinutes: Int = 0
    ) async {
        guard isAuthorized else {
            await requestAuthorization()
            guard isAuthorized else { return }
        }

        // Cancel any existing Lunifer alarm first
        await cancelAlarm()

        // ── Build the alert that appears when alarm fires ──
        let alert = AlarmPresentation.Alert(
            title: "Time to wake up",
            stopButton: AlarmButton(
                text: "Dismiss",
                textColor: .white,
                systemImageName: "moon.zzz.fill"
            ),
            secondaryButton: AlarmButton(
                text: "Snooze",
                textColor: Color(red: 0.75, green: 0.65, blue: 1.0),
                systemImageName: "clock.arrow.circlepath"
            )
        )

        // ── Build attributes with Lunifer purple tint ──
        let attributes = AlarmAttributes<LuniferAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: Color(red: 0.55, green: 0.35, blue: 0.95)
        )

        // ── Attach metadata for ML logging ──
        let metadata = LuniferAlarmMetadata(
            scheduledWakeTime: date,
            calendarEventTitle: eventTitle,
            routineMinutes: routineMinutes,
            commuteMinutes: commuteMinutes
        )

        // ── Schedule as a fixed-time alarm ──
        do {
            let _ = try await manager.schedule(
                id: UUID(),
                configuration: .alarm(
                    schedule: .fixed(date),
                    attributes: attributes,
                    metadata: metadata
                )
            )
            scheduledWakeTime = date
            print("✅ Alarm scheduled for \(date.formatted(date: .omitted, time: .shortened))")
            AlarmBehaviourLogger.shared.logScheduled(for: date)
        } catch {
            print("❌ Failed to schedule alarm: \(error.localizedDescription)")
        }
    }

    // ── MARK: Cancel Alarm ────────────────────────────────────
    func cancelAlarm() async {
        for alarm in activeAlarms {
            do {
                try manager.cancel(id: alarm.id)
            } catch {
                print("❌ Failed to cancel alarm: \(error.localizedDescription)")
            }
        }
        scheduledWakeTime = nil
    }

    // ── MARK: Listen for alarm updates ───────────────────────
    // Call this on app launch to keep activeAlarms in sync.
    // Add .task { await LuniferAlarm.shared.startMonitoring() }
    // to your root ContentView.
    func startMonitoring() async {
        for await alarms in manager.alarmUpdates {
            activeAlarms = alarms

            // Detect when alarm fires and log it for ML
            for alarm in alarms {
                if case .alerting = alarm.state {
                    AlarmBehaviourLogger.shared.logAlarmFired(at: Date())
                }
            }
        }
    }
}

// ── MARK: AlarmBehaviourLogger ────────────────────────────────
// Every snooze, dismiss, and early wake is a data point that
// feeds the ML model to improve future alarm times.

class AlarmBehaviourLogger {

    static let shared = AlarmBehaviourLogger()

    func logScheduled(for date: Date) {
        write(["type": "scheduled", "wakeTime": date, "dayOfWeek": dayOfWeek(date)])
    }

    func logAlarmFired(at date: Date) {
        write(["type": "alarm_fired", "timestamp": date, "dayOfWeek": dayOfWeek(date)])
    }

    func logSnooze(at date: Date) {
        write(["type": "snooze", "timestamp": date, "dayOfWeek": dayOfWeek(date)])
    }

    func logDismiss(at date: Date) {
        write(["type": "dismiss", "timestamp": date, "dayOfWeek": dayOfWeek(date)])
    }

    func logWokeBeforeAlarm(at date: Date) {
        write(["type": "woke_before_alarm", "timestamp": date, "dayOfWeek": dayOfWeek(date)])
    }

    private func dayOfWeek(_ date: Date) -> Int {
        Calendar.current.component(.weekday, from: date)
    }

    private func write(_ data: [String: Any]) {
        // TODO: swap placeholder with Firebase Auth UID
        let userID = "placeholder_user_id"

        // Firestore path: users/{userID}/alarmEvents/{autoID}
        // Uncomment when FirebaseFirestore is imported:
        //
        // let db = Firestore.firestore()
        // db.collection("users").document(userID)
        //   .collection("alarmEvents").addDocument(data: data)

        print("📊 Logged: \(data["type"] ?? "") at \(data["timestamp"] ?? data["wakeTime"] ?? "")")
    }
}
