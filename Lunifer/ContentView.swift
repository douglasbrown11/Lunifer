import SwiftUI
import FirebaseAuth

enum AppScreen {
    case intro, calendarChoice, auth, survey, splash, dashboard
}

struct ContentView: View {
    @State private var screen: AppScreen = .intro
    @State private var surveyAnswers = SurveyAnswers()
    @State private var preSelectedCalendar: String = ""
    @StateObject private var alarm = LuniferAlarm.shared
    @AppStorage("surveyCompleted") private var surveyCompleted = false
    @State private var authStateHandle: AuthStateDidChangeListenerHandle?

    var body: some View {
        ZStack {
            switch screen {
            case .intro:
                LuniferIntro(onFinish: { screen = .calendarChoice })
            case .calendarChoice:
                CalendarChoiceScreen(onSelect: { calendar in
                    preSelectedCalendar = calendar
                    screen = .auth
                })
                .transition(.opacity)
            case .auth:
                LuniferSignin(calendarChoice: preSelectedCalendar, onSignedIn: { isNewUser in
                    await handleSignedIn(isNewUser: isNewUser)
                }, onBack: {
                    withAnimation(.easeInOut(duration: 0.3)) { screen = .calendarChoice }
                })
            case .survey:
                LuniferSurvey(preSelectedCalendar: preSelectedCalendar, onFinish: { answers in
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
                    Task { @MainActor in
                        // An explicit sign-in owns its own routing through
                        // handleSignedIn. In particular, a newly-created account
                        // can arrive while this device still has the previous
                        // account's completed-survey flag and cached answers.
                        // Do not let the auth listener briefly route that new
                        // account through the returning-user splash.
                        if user != nil,
                           screen != .auth,
                           surveyCompleted,
                           let saved = SurveyAnswers.loadFromDefaults() {
                            await SilentPushManager.shared.syncStoredToken()
                            surveyAnswers = saved
                            screen = .splash
                            await AdaptiveAlarmStore.shared.loadFromFirestore()
                        } else if user == nil,
                                  screen != .intro,
                                  screen != .calendarChoice,
                                  screen != .auth {
                            screen = .intro
                        }
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
            // A new account intentionally clears a stale completion flag before
            // entering its survey. Only treat that reset as a sign-out when
            // Firebase no longer has an authenticated user.
            if !completed, Auth.auth().currentUser == nil {
                screen = .intro
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

    @MainActor
    private func handleSignedIn(isNewUser: Bool) async {
        await SilentPushManager.shared.syncStoredToken()
        if isNewUser {
            surveyCompleted = false
            screen = .survey
            return
        }

        do {
            if let savedAnswers = try await SurveyAnswersStore.shared.loadFromFirestore() {
                surveyAnswers = savedAnswers
                surveyAnswers.saveToDefaults()
                surveyCompleted = true
                screen = .splash
                await AdaptiveAlarmStore.shared.loadFromFirestore()
            } else {
                surveyCompleted = false
                screen = .survey
            }
        } catch {
            surveyCompleted = false
            screen = .survey
        }
    }
}
