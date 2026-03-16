import SwiftUI
import FirebaseAuth

enum AppScreen {
    case intro, auth, survey, dashboard
}

struct ContentView: View {
    @State private var screen: AppScreen = .intro
    @State private var surveyAnswers = SurveyAnswers()
    @StateObject private var alarm = LuniferAlarm.shared
    @AppStorage("surveyCompleted") private var surveyCompleted = false

    var body: some View {
        ZStack {
            switch screen {
            case .intro:
                LuniferIntro(onFinish: { screen = .auth })
            case .auth:
                LuniferAuth(onSignedIn: { screen = .survey })
            case .survey:
                LuniferSurvey(onFinish: { answers in
                    surveyAnswers = answers
                    screen = .dashboard
                })
            case .dashboard:
                LuniferDashboard(answers: $surveyAnswers, onSignOut: {
                    screen = .intro
                })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if surveyCompleted,
               Auth.auth().currentUser != nil,
               let saved = SurveyAnswers.loadFromDefaults() {
                surveyAnswers = saved
                screen = .dashboard
            }
        }
        .task {
            await LuniferAlarm.shared.startMonitoring()
        }
        // Alarm screen slides up over whatever screen is currently showing
        .fullScreenCover(isPresented: Binding(
            get: { alarm.alertingAlarm != nil },
            set: { _ in }
        )) {
            LuniferAlarmScreen()
        }
    }
}
