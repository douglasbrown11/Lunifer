import SwiftUI
import UIKit
import Firebase
import FirebaseAuth
import GoogleSignIn
import BackgroundTasks
import UserNotifications
import FeedbackPulse

// ─────────────────────────────────────────────────────────────
// AppDelegate
// ─────────────────────────────────────────────────────────────
// This SwiftUI app previously had NO UIApplicationDelegate, so Firebase's
// GoogleUtilities AppDelegateSwizzler couldn't hook incoming URL callbacks
// ("App Delegate does not conform to UIApplicationDelegate protocol"). That
// broke Firebase's MANAGED OAuth flow for Microsoft — the redirect back from
// https://lunifer-ce086.firebaseapp.com/__/auth/handler was never delivered,
// producing the "missing initial state / sessionStorage" error.
//
// Adding this delegate and forwarding open-URL callbacks to Firebase (and
// Google Sign-In) lets that flow complete. Microsoft sign-in must use Firebase's
// managed flow because Firebase rejects a self-obtained Microsoft id_token.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) { return true }
        if Auth.auth().canHandle(url) { return true }
        return false
    }
}

// "@main" tells Swift this is where the app starts
@main
struct LuniferApp: App {

    // Bridges a UIApplicationDelegate into this SwiftUI app so Firebase can
    // complete OAuth (Microsoft) URL callbacks. See AppDelegate above.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Creates one shared CalendarManager for the entire app.
    // "@StateObject" means SwiftUI owns this object and keeps it alive
    // for as long as the app is running.
    @StateObject private var calendarManager = CalendarManager()

    init() {
        FirebaseApp.configure()

        // Configure Feedback Pulse (powers the Submit Feedback screen). The fp_
        // key is a public client ingestion key and is safe to embed. Debug builds
        // report into the development environment so test feedback stays separate
        // from real production feedback.
        #if DEBUG
        FeedbackPulse.configure(apiKey: "fp_qqrl3KrWH9d5hnJl7wDsTbDmFjr4jn0gPjTQZtCA8o0", environment: .development)
        FeedbackPulse.shared.debugMode = true
        #else
        FeedbackPulse.configure(apiKey: "fp_qqrl3KrWH9d5hnJl7wDsTbDmFjr4jn0gPjTQZtCA8o0", environment: .production)
        #endif

        // Register the background task handler for overnight sleep analysis.
        // iOS will call this handler when it wakes the app in the background.
        SleepTracker.registerBackgroundTask()

        // Register the background task handler for commute duration refresh.
        // Fires ~every 10 minutes during the morning commute window so the
        // leave-reminder and delta-alert pipeline works even when the app
        // is suspended.
        CommuteManager.registerBackgroundTask()

        // One-time migration: scrub any sleep history entries whose duration
        // falls outside the realistic 3–12 hour range.  These are artefacts
        // from early development runs where the retroactive analysis window
        // had no prior baseline, causing false long-duration entries to be
        // written to UserDefaults.
        SleepHistoryStore.shared.purgeBadEntries()

        // Register the rest-day event notification category so iOS knows
        // about the "Wake me up" / "Not needed" action buttons before any
        // notification of that type is delivered.
        RestDayEventNotification.registerCategory()

        // Set the app-wide notification delegate. This must be assigned before
        // the app finishes launching so no early notifications are missed.
        UNUserNotificationCenter.current().delegate = LuniferNotificationDelegate.shared
    }

    // "body" defines what the app actually shows on screen.
    // Every SwiftUI app must have a body that returns a Scene.
    var body: some Scene {

        // WindowGroup is the standard container for an iOS app's main window.
        WindowGroup {

            // ContentView is the root of all navigation — it decides whether
            // to show the Intro, Auth, Survey, or Dashboard screen.
            ContentView()
                // ".environmentObject" makes calendarManager available to every
                // screen in the app without needing to pass it manually each time.
                .environmentObject(calendarManager)
                // ".onOpenURL" handles the URL callback from Google Sign In.
                // When the user finishes signing in via the browser, iOS sends
                // the app a URL — this passes it to Google Sign In to complete the flow.
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                    _ = Auth.auth().canHandle(url)
                }
        }
    }
}
