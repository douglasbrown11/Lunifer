import SwiftUI

enum AppScreen {
    case intro, auth, survey
}

struct ContentView: View {
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
            .task {
                await LuniferAlarm.shared.startMonitoring()
        }
    }
}


