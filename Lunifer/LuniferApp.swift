import SwiftUI
import Firebase
import FirebaseAuth
import GoogleSignIn
import BackgroundTasks

// "@main" tells Swift this is where the app starts — only one struct in the
// entire project can have this attribute.
@main
struct LuniferApp: App {

    // Creates one shared CalendarManager for the entire app.
    // "@StateObject" means SwiftUI owns this object and keeps it alive
    // for as long as the app is running.
    @StateObject private var calendarManager = CalendarManager()

    init() {
        FirebaseApp.configure()

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
