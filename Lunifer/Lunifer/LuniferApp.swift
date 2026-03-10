import SwiftUI
import Firebase

@main
struct LuniferApp: App {

    @StateObject private var calendarManager = CalendarManager()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(calendarManager)
        }
    }
}
