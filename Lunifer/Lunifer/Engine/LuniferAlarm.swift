// ─────────────────────────────────────────────────────────────
// LuniferAlarm.swift
// This file is the alarm brain of Lunifer.
// It handles everything alarm-related:
//   1. Asking the user for permission to set alarms
//   2. Scheduling the alarm at the calculated wake time
//   3. Cancelling the alarm if needed
//   4. Listening for when the alarm fires
//   5. Logging snooze/dismiss behaviour for the ML model
// ─────────────────────────────────────────────────────────────

import Foundation
import Combine   // Required for @Published property wrapper and ObservableObject
import AlarmKit  // Apple's built-in alarm framework (iOS 26+)
                 // Lets us set alarms that bypass silent mode and Do Not Disturb
                 // Just like the built-in Clock app — no special Apple approval needed
import SwiftUI

// ─────────────────────────────────────────────────────────────
// SECTION 1: ALARM METADATA
// ─────────────────────────────────────────────────────────────
// AlarmKit requires us to attach a "metadata" struct to every alarm.
// Think of metadata as a label we stick on the alarm that tells us
// WHY this alarm was set and what data was used to calculate it.
// This is also useful for the ML model — every alarm we log includes
// this context so the model can learn from it.
//
// "nonisolated" is a Swift 6 requirement — it just means this struct
// can be safely used from any part of the app without threading issues.

struct LuniferAlarmMetadata: AlarmMetadata {
    var scheduledWakeTime: Date      // The time we calculated the alarm for
    var calendarEventTitle: String   // The name of the first event tomorrow (e.g. "Team standup")
    var routineMinutes: Int          // How long the user's morning routine takes
    var commuteMinutes: Int          // How long their commute takes
}

// ─────────────────────────────────────────────────────────────
// SECTION 2: THE MAIN ALARM CLASS
// ─────────────────────────────────────────────────────────────
// This is the main class that controls everything alarm-related.
//
// "class" means it's a reference type — one shared instance across the app.
// "@MainActor" means all UI updates happen on the main thread (required for SwiftUI).
// "ObservableObject" means SwiftUI views can watch it and update automatically
//  when something changes (like when an alarm gets scheduled or fires).

@MainActor
class LuniferAlarm: ObservableObject {

    // "static let shared" means there is only ONE instance of LuniferAlarm
    // in the whole app. Any file can access it by writing LuniferAlarm.shared
    // This is called a "singleton" — one shared object everyone uses.
    static let shared = LuniferAlarm()

    // AlarmManager is Apple's AlarmKit object that actually does the scheduling.
    // We talk to it to set, cancel, and monitor alarms.
    private let manager = AlarmManager.shared

    // ── @Published variables ──────────────────────────────────
    // "@Published" means: whenever these values change, any SwiftUI view
    // that's watching them will automatically refresh.
    // Think of it like a live feed — the UI always shows the current value.

    @Published var isAuthorized: Bool = false       // Has the user granted alarm permission?
    @Published var activeAlarms: [Alarm] = []       // List of currently scheduled alarms
    @Published var scheduledWakeTime: Date? = nil   // The time the next alarm is set for

    // ─────────────────────────────────────────────────────────
    // SECTION 3: REQUESTING PERMISSION
    // ─────────────────────────────────────────────────────────
    // Before Lunifer can set any alarms, it must ask the user for permission.
    // iOS will show a popup saying "Lunifer wants to schedule alarms" with
    // Allow and Don't Allow buttons.
    // We call this function when the user finishes the survey.
    //
    // "async" means this function can wait for things (like the user tapping Allow)
    // without freezing the whole app.

    func requestAuthorization() async {

        // Check the current permission state and handle each case
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

    func scheduleAlarm(
        for date: Date,
        eventTitle: String = "your first event",
        routineMinutes: Int = 60,
        commuteMinutes: Int = 0
    ) async {

        // Step 1: Make sure we have permission first
        // If we don't, ask for it. If user still says no, stop here.
        if !isAuthorized {
            await requestAuthorization()
        }
        guard isAuthorized else { return }

        // Step 2: Cancel any existing alarm so we don't have two alarms going off
        await cancelAlarm()

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
            let _ = try await manager.schedule(
                id: UUID(),             // A unique ID for this alarm — UUID generates a random one
                configuration: .alarm(
                    schedule: .fixed(date),   // Fire at this exact time
                    attributes: attributes    // Using the design + data we set up above
                )
            )

            // If we got here without an error, the alarm was successfully scheduled
            scheduledWakeTime = date
            print("✅ Alarm set for \(date.formatted(date: .omitted, time: .shortened))")

            // Log the scheduling event for the ML model
            AlarmBehaviourLogger.shared.logScheduled(for: date)

        } catch {
            // Something went wrong — print the error for debugging in Xcode console
            print("❌ Failed to schedule alarm: \(error.localizedDescription)")
        }
    }

    // ─────────────────────────────────────────────────────────
    // SECTION 5: CANCELLING THE ALARM
    // ─────────────────────────────────────────────────────────
    // Cancels all active Lunifer alarms.
    // Called before scheduling a new alarm, or if the user
    // manually turns off the alarm from the dashboard.

    func cancelAlarm() async {
        for alarm in activeAlarms {
            do {
                try manager.cancel(id: alarm.id)  // Tell AlarmKit to remove this alarm
            } catch {
                print("❌ Failed to cancel alarm: \(error.localizedDescription)")
            }
        }
        scheduledWakeTime = nil  // Clear the displayed wake time in the UI
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

    func startMonitoring() async {
        for await alarms in manager.alarmUpdates {

            // Update our local list of active alarms so the UI stays in sync
            activeAlarms = alarms

            // Check if any alarm is currently firing (alerting = alarm is going off right now)
            for alarm in alarms {
                if case .alerting = alarm.state {
                    // The alarm just fired — log it for the ML model
                    AlarmBehaviourLogger.shared.logAlarmFired(at: Date())
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────
// SECTION 7: BEHAVIOUR LOGGER
// ─────────────────────────────────────────────────────────────
// This class records what the user does with their alarm every day.
// Every snooze, every dismiss, every time they wake up before the alarm —
// all of it gets saved to Firestore as a data point.
//
// Over time this builds a picture of the user's real sleep behaviour,
// which is what the ML model uses to personalise the alarm time.
//
// Example data after 30 days:
//   Monday + snoozed 3 times = alarm was too early on Mondays
//   Friday + dismissed immediately = alarm time was perfect on Fridays
//   Tuesday + woke before alarm = alarm was too late on Tuesdays
//
// The ML model reads all of this and adjusts future alarm times accordingly.

class AlarmBehaviourLogger {

    // Another singleton — one shared logger for the whole app
    static let shared = AlarmBehaviourLogger()

    // Called when a new alarm is scheduled for the night
    func logScheduled(for date: Date) {
        write(["type": "scheduled", "wakeTime": date, "dayOfWeek": dayOfWeek(date)])
    }

    // Called when the alarm actually fires (goes off)
    func logAlarmFired(at date: Date) {
        write(["type": "alarm_fired", "timestamp": date, "dayOfWeek": dayOfWeek(date)])
    }

    // Called when the user taps Snooze
    // More snoozes = alarm was too early = ML should push it later
    func logSnooze(at date: Date) {
        write(["type": "snooze", "timestamp": date, "dayOfWeek": dayOfWeek(date)])
    }

    // Called when the user taps Dismiss without snoozing
    // Clean dismiss = good alarm time = ML should keep it similar
    func logDismiss(at date: Date) {
        write(["type": "dismiss", "timestamp": date, "dayOfWeek": dayOfWeek(date)])
    }

    // Called when HealthKit detects the user woke up before the alarm
    // (we'll build this when we add HealthKit integration later)
    // Woke before alarm = alarm was too late = ML should move it earlier
    func logWokeBeforeAlarm(at date: Date) {
        write(["type": "woke_before_alarm", "timestamp": date, "dayOfWeek": dayOfWeek(date)])
    }

    // ── Private helpers ──────────────────────────────────────

    // Returns the day of week as a number (1 = Sunday, 2 = Monday... 7 = Saturday)
    // The ML model uses this because alarm behaviour differs by day
    // (e.g. people snooze more on Mondays than Fridays)
    private func dayOfWeek(_ date: Date) -> Int {
        Calendar.current.component(.weekday, from: date)
    }

    // Saves the data to Firestore (Firebase's database)
    // Right now it just prints to the console — uncomment the Firestore
    // lines below once you're ready to wire up the database
    private func write(_ data: [String: Any]) {

        // TODO: Replace this with the real Firebase Auth user ID
        // You'll get this from FirebaseAuth.auth().currentUser?.uid
        // let userID = "placeholder_user_id"  // TODO: replace with FirebaseAuth.auth().currentUser?.uid

        // ── Firestore write (uncomment when ready) ──
        // This saves the event to: users/{userID}/alarmEvents/{autoID}
        // Each event is a separate document in Firestore
        //
        // import FirebaseFirestore  ← add this at the top of the file
        //
        // let db = Firestore.firestore()
        // db.collection("users")
        //   .document(userID)
        //   .collection("alarmEvents")
        //   .addDocument(data: data) { error in
        //       if let error = error {
        //           print("❌ Failed to save alarm event: \(error)")
        //       } else {
        //           print("✅ Alarm event saved to Firestore")
        //       }
        //   }

        // For now, just print to the Xcode console so we can see what's being logged
        print("📊 Alarm event: \(data["type"] ?? "") at \(data["timestamp"] ?? data["wakeTime"] ?? "")")
    }
}
