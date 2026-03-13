import SwiftUI

enum AppScreen {
    case intro, auth, survey
}

struct ContentView: View {
    @State private var screen: AppScreen = .intro

    var body: some View {
        ZStack {
            switch screen {
            case .intro:
                LuniferIntro(onFinish: { screen = .auth })
            case .auth:
                LuniferAuth(onSignedIn: { screen = .survey })
            case .survey:
                LuniferSurvey()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await LuniferAlarm.shared.startMonitoring()
        }
    }
}
