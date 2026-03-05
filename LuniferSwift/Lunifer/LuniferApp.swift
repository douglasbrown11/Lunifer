import SwiftUI
import FirebaseCore

enum AppScreen {
    case intro
    case auth
    case survey
}

@main
struct LuniferApp: App {

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var screen: AppScreen = .intro

    var body: some View {
        switch screen {
        case .intro:
            LuniferIntro(onFinish: { screen = .auth })
        case .auth:
            LuniferAuth(onSignedIn: { screen = .survey })
        case .survey:
            LuniferSurvey()
        }
    }
}
