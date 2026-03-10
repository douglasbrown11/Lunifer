import SwiftUI
import FirebaseFirestore

// ── MARK: Models ─────────────────────────────────────────────

struct TimeValue {
    var hours: Int
    var minutes: Int
    var auto: Bool
}

struct SurveyAnswers {
    var age: String       = "18"
    var lifestyle: String? = nil
    var calendar: String?  = nil
    var sleep   = TimeValue(hours: 8, minutes: 0,  auto: false)
    var routine = TimeValue(hours: 1, minutes: 0,  auto: false)
    var commute = TimeValue(hours: 0, minutes: 30, auto: false)
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

// ── MARK: Calendar brand icons ───────────────────────────────

private struct AppleCalendarIcon: View {
    var body: some View {
        Image(systemName: "apple.logo")
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(.white)
    }
}

private struct GoogleCalendarIcon: View {
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3).fill(Color.white)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color(red: 0.102, green: 0.451, blue: 0.910))
                    .frame(height: 7)
                Spacer()
                Text("31")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(Color(red: 0.102, green: 0.451, blue: 0.910))
                    .padding(.bottom, 2)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

private struct OutlookIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: 0, green: 0.471, blue: 0.831))
                .frame(width: 22, height: 22)
            Text("O")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
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
        var onFinish: (() -> Void)? = nil

        @EnvironmentObject private var calendarManager: CalendarManager

        @State private var step      = 0
        @State private var saving    = false
        @State private var saveError: String? = nil
        @State private var completed = false
        @State private var answers   = SurveyAnswers()
        
        private var showCommute: Bool {
            answers.lifestyle == "student" || answers.lifestyle == "commuter"
        }
        private var totalSteps: Int  { showCommute ? 6 : 5 }
        private var isLastStep: Bool { step == totalSteps - 1 }
        
        private var canNext: Bool {
            switch step {
            case 0: return !answers.age.isEmpty && (Int(answers.age) ?? 0) > 0
            case 1: return answers.lifestyle != nil
            case 2: return answers.calendar  != nil
            default: return true
            }
        }
        
        var body: some View {
            ZStack {
                LuniferBackground()
                
                if completed {
                    LuniferDashboard(answers: $answers)
                        .transition(.opacity.combined(with: .offset(y: 20)))
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            
                            SurveyStepDots(total: totalSteps, current: step)
                                .padding(.bottom, 24)
                            
                            // ── Step content ─────────────────────
                            stepContent
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
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
                        .padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.5), value: completed)
        }
        
        // ── MARK: Step content ───────────────────────────────────
        
        @ViewBuilder
        private var stepContent: some View {
            switch step {
            case 0: stepAge
            case 1: stepLifestyle
            case 2: stepCalendar
            case 3: stepSleep
            case 4: stepRoutine
            case 5: stepCommute
            default: EmptyView()
            }
        }
        
        // Step 0 — Age
        private var stepAge: some View {
            VStack(spacing: 0) {
                Text("How old are you?")
                    .font(.custom("Cormorant Garamond", size: 26))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 36)

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
                .padding(.bottom, 36)
            }
        }
        
        
        // Step 1 — Lifestyle
        private var stepLifestyle: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Which of these best describes you?")
                    .font(.custom("Cormorant Garamond", size: 26))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.95))
                    .padding(.bottom, 36)
                    .padding(.horizontal, 50)
                
                VStack(spacing: 10) {
                    ForEach([
                        ("student",     "I am a student"),
                        ("wfh",         "I work from home"),
                        ("commuter",    "I commute to work sometimes or most days"),
                        ("not_working", "I'm not working right now"),
                    ], id: \.0) { id, label in
                        OptionCard(isSelected: answers.lifestyle == id) {
                            answers.lifestyle = id
                        } content: {
                            Text(label)
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(answers.lifestyle == id
                                                 ? Color.white.opacity(0.95)
                                                 : Color.white.opacity(0.7))
                        }
                    }
                }
                .padding(.bottom, 36)
                .padding(.horizontal, 40)
            }
        }
        
        // Step 2 — Calendar
        private var stepCalendar: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Which calendar do you use?")
                    .font(.custom("Cormorant Garamond", size: 26))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.95))
                    .padding(.bottom, 10)
                    .padding(.horizontal, 80)
                
                Text("Lunifer will sync with your calendar to automatically adapt your alarm around early meetings, late nights, and days off.")
                    .font(.custom("DM Sans", size: 14))
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.4))
                    .lineSpacing(5)
                    .padding(.bottom, 36)
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
                .padding(.bottom, 36)
                .padding(.horizontal, 36)
            }
        }
        
        @ViewBuilder
        private func calendarCard<Icon: View>(id: String, name: String, @ViewBuilder icon: () -> Icon) -> some View {
            let iconView = icon()
            OptionCard(isSelected: answers.calendar == id) {
                answers.calendar = id
                // When the user picks Apple Calendar, request EventKit access immediately.
                if id == "apple" && calendarManager.authorizationStatus == .notDetermined {
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
        
        // Step 3 — Sleep
        private var stepSleep: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("How long do you sleep to feel your best?")
                    .font(.custom("Cormorant Garamond", size: 26))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.95))
                    .padding(.bottom, 10)
                    .padding(.horizontal, 75)
                
                
                TimeScalePicker(value: $answers.sleep,
                                autoLabel: "I'm not sure — let Lunifer learn this")
                .padding(.bottom, 36)
                .padding(.horizontal, 36)
            }
        }
        
        // Step 4 — Morning routine
        private var stepRoutine: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("How long does your morning routine take?")
                    .font(.custom("Cormorant Garamond", size: 26))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.95))
                    .padding(.bottom, 10)
                    .padding(.horizontal, 50)
                
                
                
                TimeScalePicker(value: $answers.routine,
                                autoLabel: "Not sure — let Lunifer figure this out")
                .padding(.bottom, 36)
                .padding(.horizontal, 36)
            }
        }
        
        // Step 5 — Commute (student / commuter only)
        private var stepCommute: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("How long is your commute?")
                    .font(.custom("Cormorant Garamond", size: 26))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.95))
                    .padding(.bottom, 36)
                    .padding(.horizontal, 36)
                
                TimeScalePicker(value: $answers.commute,
                                autoLabel: "Let Lunifer calculate this from my location")
                .padding(.bottom, 36)
                .padding(.horizontal, 36)
            }
        }
        
        // ── MARK: Navigation ─────────────────────────────────────
        
        private func advance() {
            step += 1
        }
        
        private func goBack() {
            if step > 0 { step -= 1 }
        }
        
        // ── MARK: Firestore save ─────────────────────────────────
        // Mirrors handleFinish() in luniferSurvey.jsx exactly
        
        private func handleFinish() {
            Task { @MainActor in
                saving    = true
                saveError = nil
                
                let data: [String: Any] = [
                    "age":       Int(answers.age) ?? 0,
                    "lifestyle": answers.lifestyle ?? "",
                    "calendar":  answers.calendar  ?? "",
                    "sleep":   ["hours": answers.sleep.hours,
                                "minutes": answers.sleep.minutes,
                                "auto": answers.sleep.auto],
                    "routine": ["hours": answers.routine.hours,
                                "minutes": answers.routine.minutes,
                                "auto": answers.routine.auto],
                    "commute": ["hours": answers.commute.hours,
                                "minutes": answers.commute.minutes,
                                "auto": answers.commute.auto],
                    "createdAt": Date(),
                ]
                
                do {
                    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                        Firestore.firestore().collection("users").addDocument(data: data) { error in
                            if let error { cont.resume(throwing: error) }
                            else         { cont.resume() }
                        }
                    }
                    completed = true
                    onFinish?()
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
}
