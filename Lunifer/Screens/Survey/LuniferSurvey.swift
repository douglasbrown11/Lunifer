import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import UIKit

// ── MARK: Models ─────────────────────────────────────────────

struct TimeValue: Codable {
    var hours: Int
    var minutes: Int
    var auto: Bool
}

struct SurveyAnswers: Codable {
    var age: String        = "18"
    var lifestyle: String? = nil
    var wakeDays: [String] = ["mon", "tue", "wed", "thu", "fri"]
    var calendar: String?  = nil
    var sleep   = TimeValue(hours: 8, minutes: 0,  auto: false)
    var routine = TimeValue(hours: 1, minutes: 0,  auto: false)
    var commute = TimeValue(hours: 0, minutes: 30, auto: false)

    static func loadFromDefaults() -> SurveyAnswers? {
        SurveyAnswersStore.shared.loadFromDefaults()
    }

    func saveToDefaults() {
        SurveyAnswersStore.shared.saveToDefaults(self)
    }

    /// Syncs the current answers to Firestore under the logged-in user's document.
    /// Uses merge: true so only changed fields are overwritten, not the whole document.
    func saveToFirestore() {
        SurveyAnswersStore.shared.syncProfile(self)
    }
}

// ── MARK: Step indicator ─────────────────────────────────────

private struct SurveyStepDots: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(
                        i == current
                        ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.9)
                        : i < current
                        ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.4)
                        : Color.white.opacity(0.15)
                    )
                    .frame(width: i == current ? 40 : 28, height: 3)
                    .animation(.easeInOut(duration: 0.4), value: current)
            }
        }
    }
}

// ── MARK: Option card (lifestyle + calendar) ─────────────────

struct OptionCard<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected
                              ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.12)
                              : Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected
                                        ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.8)
                                        : Color.white.opacity(0.08),
                                        lineWidth: 1.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

private struct WeekdayButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.custom("DM Sans", size: 15).weight(.medium))
                .foregroundColor(isSelected ? Color.white.opacity(0.95) : Color.white.opacity(0.45))
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(isSelected
                              ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.22)
                              : Color.white.opacity(0.03))
                        .overlay(
                            Circle()
                                .stroke(
                                    isSelected
                                    ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.75)
                                    : Color.white.opacity(0.08),
                                    lineWidth: 1.5
                                )
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// ── MARK: Time picker ────────────────────────────────────────

struct TimeButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18))
                .foregroundColor(Color.white.opacity(0.6))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

struct TimeScalePicker: View {
    @Binding var value: TimeValue
    let autoLabel: String

    var body: some View {
        VStack(spacing: 0) {

            // Auto toggle — mirrors the .auto-toggle div in React
            HStack(spacing: 12) {
                Toggle("", isOn: $value.auto)
                    .labelsHidden()
                    .tint(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.8))

                Text(autoLabel)
                    .font(.custom("DM Sans", size: 14))
                    .foregroundColor(value.auto
                                     ? Color.white.opacity(0.85)
                                     : Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(value.auto
                          ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.08)
                          : Color.white.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(value.auto
                                    ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.6)
                                    : Color.white.opacity(0.06),
                                    lineWidth: 1.5)
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: value.auto)

            // Hours + minutes pickers — mirrors .time-picker in React
            if !value.auto {
                HStack(alignment: .center, spacing: 16) {

                    // Hours (buttons on LEFT of number, matching React)
                    VStack(spacing: 10) {
                        Text("HOURS")
                            .font(.custom("DM Sans", size: 11))
                            .foregroundColor(Color.white.opacity(0.3))
                            .kerning(1)

                        HStack(spacing: 8) {
                            VStack(spacing: 6) {
                                TimeButton(label: "↑") { value.hours = min(23, value.hours + 1) }
                                TimeButton(label: "↓") { value.hours = max(0,  value.hours - 1) }
                            }
                            Text(String(format: "%02d", value.hours))
                                .font(.custom("Roboto", size: 44).weight(.light))
                                .foregroundColor(Color.white.opacity(0.95))
                                .monospacedDigit()
                                .frame(minWidth: 56, alignment: .center)
                        }
                    }

                    // Colon separator
                    Text(":")
                        .font(.custom("Roboto", size: 32).weight(.light))
                        .foregroundColor(Color.white.opacity(0.2))
                        .padding(.top, 24)

                    // Minutes (buttons on RIGHT of number, matching React)
                    VStack(spacing: 10) {
                        Text("MINUTES")
                            .font(.custom("DM Sans", size: 11))
                            .foregroundColor(Color.white.opacity(0.3))
                            .kerning(1)

                        HStack(spacing: 8) {
                            Text(String(format: "%02d", value.minutes))
                                .font(.custom("Roboto", size: 44).weight(.light))
                                .foregroundColor(Color.white.opacity(0.95))
                                .monospacedDigit()
                                .frame(minWidth: 56, alignment: .center)
                            VStack(spacing: 6) {
                                TimeButton(label: "↑") { value.minutes = min(55, value.minutes + 5) }
                                TimeButton(label: "↓") { value.minutes = max(0,  value.minutes - 5) }
                            }
                        }
                    }
                }
                .padding(.top, 20)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: value.auto)
    }
}

// ── MARK: LuniferSurvey ──────────────────────────────────────

struct LuniferSurvey: View {
        var onFinish: ((SurveyAnswers) -> Void)? = nil
        @AppStorage("surveyCompleted") private var surveyCompleted = false

        @EnvironmentObject private var calendarManager: CalendarManager
        @Environment(\.openURL) private var openURL

        @StateObject private var locationManager = LocationManager()

        @State private var step      = 0
        @State private var saving    = false
        @State private var saveError: String? = nil
        @State private var answers   = SurveyAnswers()
        @State private var showLocationDeniedAlert = false
        @State private var showLocationUpgradeAlert = false
        @State private var showLocationSettingsAlert = false
        @State private var hasShownLocationDeniedAlert = false
        
        private var showCommute: Bool {
            answers.lifestyle == "student" || answers.lifestyle == "commuter"
        }
        /// Morning routine step is skipped for users who are not working.
        private var showRoutine: Bool {
            answers.lifestyle != "not_working"
        }
        private var totalSteps: Int {
            var count = 5  // age, lifestyle, wakeDays, calendar, sleep — always shown
            if showRoutine { count += 1 }
            if showCommute { count += 1 }
            return count
        }
        private var isLastStep: Bool { step == totalSteps - 1 }
        
        private var canNext: Bool {
            switch step {
            case 0: return !answers.age.isEmpty && (Int(answers.age) ?? 0) > 0
            case 1: return answers.lifestyle != nil
            case 2: return !answers.wakeDays.isEmpty
            case 3: return answers.calendar  != nil
            case 6: // commute step
                if answers.commute.auto {
                    return locationManager.authorizationStatus == .authorizedAlways
                } else {
                    return answers.commute.hours > 0 || answers.commute.minutes > 0
                }
            default: return true
            }
        }
        
        var body: some View {
            ZStack {
                LuniferBackground()

                ScrollView {
                        VStack(spacing: 0) {
                            
                            SurveyStepDots(total: totalSteps, current: step)
                                .padding(.bottom, 16)
                            
                            // ── Step content ─────────────────────
                            stepContent
                                .frame(maxWidth: .infinity, alignment: .center)
                            
                            // ── Save error ───────────────────────
                            if let error = saveError {
                                Text(error)
                                    .font(.custom("DM Sans", size: 13))
                                    .foregroundColor(Color(red: 1, green: 0.392, blue: 0.392).opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .padding(.bottom, 12)
                            }
                            
                            // ── Primary button ───────────────────
                            Button {
                                isLastStep ? handleFinish() : advance()
                            } label: {
                                ZStack {
                                    if saving {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text(isLastStep ? "Finish Setup →" : "Continue →")
                                            .font(.custom("DM Sans", size: 15).weight(.medium))
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(LinearGradient(
                                            colors: [
                                                Color(red: 0.471, green: 0.314, blue: 0.863).opacity(0.9),
                                                Color(red: 0.314, green: 0.196, blue: 0.706).opacity(0.9),
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                        .opacity(canNext && !saving ? 1 : 0.35)
                                )
                            }
                            .disabled(!canNext || saving)
                            .padding(.bottom, 12)
                            
                            // ── Back button ──────────────────────
                            if step > 0 {
                                Button { goBack() } label: {
                                    Text("← Back")
                                        .font(.custom("DM Sans", size: 14))
                                        .foregroundColor(Color.white.opacity(0.3))
                                        .padding(.vertical, 8)
                                }
                            }
                        }
                        .frame(maxWidth: 480)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .alert("Always Allow Location Access Required", isPresented: $showLocationDeniedAlert) {
                Button("OK") {
                    hasShownLocationDeniedAlert = true
                    answers.commute.auto = false
                    answers.commute.hours = 0
                    answers.commute.minutes = 0
                }
            } message: {
                Text("In order for Lunifer to learn this, you must select \"Always Allow\" so Lunifer can track your commute.")
            }
            .alert("Turn On Location Access in Settings", isPresented: $showLocationSettingsAlert) {
                Button("Not Now", role: .cancel) {
                    answers.commute.auto = false
                }
                Button("Open Settings") {
                    answers.commute.auto = false
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settingsURL)
                    }
                }
            } message: {
                Text("Location access was previously denied. iOS will not show the permission prompt again. Open Settings and change Location to \"Always\" to let Lunifer learn your commute.")
            }
            .alert("Allow Always to Learn Your Commute", isPresented: $showLocationUpgradeAlert) {
                Button("Not Now", role: .cancel) {
                    answers.commute.auto = false
                }
                Button("Continue") {
                    locationManager.requestAlwaysAuthorization()
                }
            } message: {
                Text("You selected \"Allow While Using App.\" To let Lunifer automatically learn your commute, please choose \"Always Allow\" on the next prompt.")
            }
        }
        
        // ── MARK: Step content ───────────────────────────────────
        
        @ViewBuilder
        private var stepContent: some View {
            switch step {
            case 0: stepAge
            case 1: stepLifestyle
            case 2: stepWakeDays
            case 3: stepCalendar
            case 4: stepSleep
            case 5: stepRoutine
            case 6: stepCommute
            default: EmptyView()
            }
        }
        
        // Step 0 — Age Question
        private var stepAge: some View {
            VStack(spacing: 0) {
                Text("How old are you?")
                    .font(.custom("Cormorant Garamond", size: 22))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 20)

                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1.5)
                        )

                    Picker("Age", selection: Binding(
                        get: { Int(answers.age) ?? 18 },
                        set: { answers.age = String($0) }
                    )) {
                        ForEach(1...125, id: \.self) { age in
                            Text("\(age)")
                                .font(.custom("Roboto", size: 22).weight(.light))
                                .tag(age)
                        }
                    }
                    .pickerStyle(.wheel)
                    .colorScheme(.dark)
                    .frame(height: 160)
                    .clipped()
                }
                .frame(width: 160, height: 160)
                .padding(.bottom, 24)
            }
        }
        
        
        // Step 1 — Lifestyle - Commute or Not question
        private var stepLifestyle: some View {
            VStack(alignment: .center, spacing: 0) {
                Text("Which of these best describes you?")
                    .font(.custom("Cormorant Garamond", size: 22))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 20)

                VStack(spacing: 10) {
                    ForEach([
                        ("student",     "I am a student"),
                        ("wfh",         "I work from home"),
                        ("commuter",    "I commute to work sometimes or most days"),
                        ("not_working", "I'm not working right now"),
                    ], id: \.0) { id, label in
                        OptionCard(isSelected: answers.lifestyle == id) {
                            let previous = answers.lifestyle
                            answers.lifestyle = id
                            // If switching TO not_working, zero out routine so the skipped
                            // step doesn't silently subtract time from the alarm calculation.
                            if id == "not_working" {
                                answers.routine = TimeValue(hours: 0, minutes: 0, auto: false)
                            }
                            // If switching AWAY FROM not_working, restore the routine default
                            // so the newly-visible step starts at a sensible value.
                            if previous == "not_working" && id != "not_working" {
                                answers.routine = TimeValue(hours: 1, minutes: 0, auto: false)
                            }
                        } content: {
                            Text(label)
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(answers.lifestyle == id
                                                 ? Color.white.opacity(0.95)
                                                 : Color.white.opacity(0.7))
                        }
                    }
                }
                .padding(.bottom, 24)
                .padding(.horizontal, 40)
            }
        }

        // Step 2 — Wake-up days
        private var stepWakeDays: some View {
            let weekdays = [
                ("mon", "M"),
                ("tue", "T"),
                ("wed", "W"),
                ("thu", "T"),
                ("fri", "F"),
                ("sat", "S"),
                ("sun", "S")
            ]

            return VStack(alignment: .center, spacing: 0) {
                Text("What days of the week should Lunifer to wake you up?")
                    .font(.custom("Cormorant Garamond", size: 22))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 16)
                    .padding(.horizontal, 40)

                HStack(spacing: 10) {
                    ForEach(weekdays, id: \.0) { id, label in
                        WeekdayButton(label: label, isSelected: answers.wakeDays.contains(id)) {
                            toggleWakeDay(id)
                        }
                    }
                }
                .padding(.bottom, 14)
                .padding(.horizontal, 16)

                if answers.wakeDays.isEmpty {
                    Text("Select at least one day to continue.")
                        .font(.custom("DM Sans", size: 13))
                        .foregroundColor(Color.white.opacity(0.35))
                        .padding(.horizontal, 32)
                        .padding(.bottom, 24)
                } else {
                    Spacer().frame(height: 24)
                }
            }
        }

        // Step 3 — Calendar Question
        private var stepCalendar: some View {
            VStack(alignment: .center, spacing: 0) {
                Text("Which calendar do you use?")
                    .font(.custom("Cormorant Garamond", size: 22))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)

                Text("Lunifer will sync with your calendar to automatically adapt your alarm around early meetings, late nights, and days off.")
                    .font(.custom("DM Sans", size: 13))
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 20)
                    .padding(.horizontal, 40)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    calendarCard(id: "apple",   name: "Apple Calendar")  { AppleCalendarIcon() }
                    calendarCard(id: "google",  name: "Google Calendar") { GoogleCalendarIcon() }
                    calendarCard(id: "outlook", name: "Outlook")         { OutlookIcon() }
                    calendarCard(id: "none",    name: "I don't use one") {
                        Text("—")
                            .font(.system(size: 20))
                            .foregroundColor(Color.white.opacity(0.7))
                            .frame(width: 22, alignment: .center)
                    }
                }
                .padding(.bottom, 24)
                .padding(.horizontal, 50)
            }
        }
        
        @ViewBuilder
        private func calendarCard<Icon: View>(id: String, name: String, @ViewBuilder icon: () -> Icon) -> some View {
            let iconView = icon()
            OptionCard(isSelected: answers.calendar == id) {
                answers.calendar = id
                // When the user picks Apple Calendar, request EventKit access immediately.
                if id != "none" && calendarManager.authorizationStatus == .notDetermined {
                    Task { await calendarManager.requestAccess() }
                }
            } content: {
                HStack(spacing: 12) {
                    iconView.frame(width: 28, alignment: .center)
                    Text(name)
                        .font(.custom("DM Sans", size: 14))
                        .foregroundColor(answers.calendar == id
                                         ? Color.white.opacity(0.95)
                                         : Color.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    // Show a live status badge when Apple Calendar is selected
                    if id == "apple" && answers.calendar == "apple" {
                        Spacer()
                        Image(systemName: calendarManager.authorizationStatus == .authorized
                              ? "checkmark.circle.fill"
                              : calendarManager.authorizationStatus == .denied
                              ? "xmark.circle.fill"
                              : "clock.fill")
                            .foregroundColor(calendarManager.authorizationStatus == .authorized
                                             ? Color(red: 0.4, green: 0.9, blue: 0.5)
                                             : calendarManager.authorizationStatus == .denied
                                             ? Color(red: 1.0, green: 0.4, blue: 0.4)
                                             : Color.white.opacity(0.4))
                            .font(.system(size: 15))
                            .animation(.easeInOut(duration: 0.3), value: calendarManager.authorizationStatus)
                    }
                }
            }
        }
        
        // Step 4 — Sleep
        private var stepSleep: some View {
            VStack(alignment: .center, spacing: 0) {
                Text("How long do you sleep to feel your best?")
                    .font(.custom("Cormorant Garamond", size: 22))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 16)

                TimeScalePicker(value: $answers.sleep,
                                autoLabel: "I'm not sure — let Lunifer learn this")
                .padding(.bottom, 24)
                .padding(.horizontal, 40)
            }
        }
        
        // Step 5 — Morning routine
        private var stepRoutine: some View {
            VStack(alignment: .center, spacing: 0) {
                Text("How long does your morning routine take?")
                    .font(.custom("Cormorant Garamond", size: 22))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 16)

                TimeScalePicker(value: $answers.routine,
                                autoLabel: "Not sure — let Lunifer figure this out")
                .padding(.bottom, 24)
                .padding(.horizontal, 40)
            }
        }
        
        // Step 6 — Commute (student / commuter only)
        private var stepCommute: some View {
            VStack(alignment: .center, spacing: 0) {
                Text("How long is your commute?")
                    .font(.custom("Cormorant Garamond", size: 22))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 16)

                TimeScalePicker(value: $answers.commute,
                                autoLabel: "Let Lunifer calculate this from my location")
                .padding(.horizontal, 40)
                .onChange(of: answers.commute.auto) { _, isAuto in
                    guard isAuto else { return }
                    requestCommuteAuthorizationIfNeeded()
                }
                .onAppear {
                    if answers.commute.auto {
                        requestCommuteAuthorizationIfNeeded()
                    }
                }
                .onChange(of: locationManager.authorizationStatus) { _, status in
                    guard answers.commute.auto else { return }
                    if status == .authorizedWhenInUse {
                        showLocationUpgradeAlert = true
                    } else if status == .denied || status == .restricted {
                        showLocationDeniedAlert = true
                    }
                }

                // ── Location permission status hint ───────────
                if answers.commute.auto && locationManager.authorizationStatus == .authorizedAlways {
                    Label("Location access granted", systemImage: "checkmark.circle.fill")
                        .font(.custom("DM Sans", size: 13))
                        .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.5))
                        .padding(.top, 14)
                        .padding(.horizontal, 40)
                        .transition(.opacity)
                } else if !answers.commute.auto && answers.commute.hours == 0 && answers.commute.minutes == 0 {
                    Text("Enter a non-zero commute time to continue.")
                        .font(.custom("DM Sans", size: 13))
                        .foregroundColor(Color.white.opacity(0.35))
                        .padding(.top, 14)
                        .padding(.horizontal, 40)
                        .transition(.opacity)
                }

                Spacer().frame(height: 24)
            }
        }
        
        // ── MARK: Navigation ─────────────────────────────────────
        
        private func advance() {
            step += 1
        }
        
        private func goBack() {
            if step > 0 { step -= 1 }
        }

        private func toggleWakeDay(_ day: String) {
            if answers.wakeDays.contains(day) {
                answers.wakeDays.removeAll { $0 == day }
            } else {
                let orderedDays = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
                answers.wakeDays.append(day)
                answers.wakeDays.sort {
                    (orderedDays.firstIndex(of: $0) ?? 0) < (orderedDays.firstIndex(of: $1) ?? 0)
                }
            }
        }

        private func requestCommuteAuthorizationIfNeeded() {
            switch locationManager.authorizationStatus {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse:
                showLocationUpgradeAlert = true
            case .authorizedAlways:
                break
            case .denied, .restricted:
                if hasShownLocationDeniedAlert {
                    showLocationSettingsAlert = true
                } else {
                    showLocationDeniedAlert = true
                }
            @unknown default:
                break
            }
        }
        
        // ── MARK: Firestore save ─────────────────────────────────
        // Mirrors handleFinish() in luniferSurvey.jsx exactly
        
        private func handleFinish() {
            guard Auth.auth().currentUser?.uid != nil else {
                saveError = "Not signed in. Please sign in and try again."
                return
            }
            Task { @MainActor in
                saving    = true
                saveError = nil

                do {
                    try await SurveyAnswersStore.shared.saveInitialProfile(answers)
                    answers.saveToDefaults()
                    surveyCompleted = true
                    await LuniferAlarm.shared.requestAuthorization()
                    onFinish?(answers)
                } catch {
                    saveError = "Something went wrong saving your data. Please try again."
                }
                
                saving = false
            }
        }
    }
    
// ── MARK: Preview ────────────────────────────────────────────

#Preview {
    LuniferSurvey()
        .environmentObject(CalendarManager())
}
