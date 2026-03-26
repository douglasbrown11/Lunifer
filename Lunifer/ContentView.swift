import SwiftUI
import FirebaseAuth

enum AppScreen {
    case intro, auth, survey, splash, dashboard
}

struct ContentView: View {
    @State private var screen: AppScreen = .intro
    @State private var surveyAnswers = SurveyAnswers()
    @StateObject private var alarm = LuniferAlarm.shared
    @AppStorage("surveyCompleted") private var surveyCompleted = false
    @State private var authStateHandle: AuthStateDidChangeListenerHandle?

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
            case .splash:
                ReturningUserSplash(onFinish: {
                    withAnimation(.easeInOut(duration: 0.7)) { screen = .dashboard }
                })
                .transition(.opacity)
            case .dashboard:
                LuniferMain(answers: $surveyAnswers)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if authStateHandle == nil {
                authStateHandle = Auth.auth().addStateDidChangeListener { _, user in
                    if user != nil, surveyCompleted, let saved = SurveyAnswers.loadFromDefaults() {
                        surveyAnswers = saved
                        screen = .splash
                    } else if user == nil, surveyCompleted {
                        screen = .auth
                    }
                }
            }

            if surveyCompleted,
               Auth.auth().currentUser != nil,
               let saved = SurveyAnswers.loadFromDefaults() {
                surveyAnswers = saved
                screen = .splash
            }
        }
        .onDisappear {
            if let authStateHandle {
                Auth.auth().removeStateDidChangeListener(authStateHandle)
                self.authStateHandle = nil
            }
        }
        .onChange(of: surveyCompleted) { _, completed in
            if !completed { screen = .intro }
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
