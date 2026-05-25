import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import CoreMotion
import UIKit
import UserNotifications

// ── MARK: Models ─────────────────────────────────────────────

struct TimeValue: Codable, Equatable {
    var hours: Int
    var minutes: Int
    var auto: Bool
}

struct SurveyAnswers: Codable {
    var age: String        = "2000-01-01"
    var lifestyle: String? = nil
    var wakeDays: [String] = ["mon", "tue", "wed", "thu", "fri"]
    var calendar: String?  = nil
    var sleep   = TimeValue(hours: 8, minutes: 0,  auto: false)
    var routine = TimeValue(hours: 1, minutes: 0,  auto: false)
    var commute = TimeValue(hours: 0, minutes: 30, auto: true)
    /// Transport mode for commute: "drive", "transit", "walk", or "bike"
    var commuteMode: String = ""

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

// ── MARK: Looping minute picker ──────────────────────────────
// SwiftUI's wheel Picker stops at each end. This UIViewRepresentable
// wraps UIPickerView with 60 000 virtual rows so the wheel feels
// infinite and wraps 59 → 00 → 59 naturally.

private struct LoopingMinutePicker: UIViewRepresentable {
    @Binding var selection: Int   // always kept in 0…59

    // Total virtual rows — must be divisible by 60 so modulo is clean.
    private static let rowCount = 60_000
    // Start position: exactly halfway, aligned to minute 00.
    // 30 000 % 60 == 0, so row 30 000 maps to minute 00.
    private static let midStart = rowCount / 2  // = 30 000

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate   = context.coordinator
        picker.backgroundColor = .clear
        // Position wheel so the current minute is visible in the centre.
        picker.selectRow(Self.midStart + selection, inComponent: 0, animated: false)
        return picker
    }

    func updateUIView(_ uiView: UIPickerView, context: Context) {
        // Sync if an external write changed the value (e.g. "No" reset to 00).
        let currentRow = uiView.selectedRow(inComponent: 0)
        if currentRow % 60 != selection {
            uiView.selectRow(Self.midStart + selection, inComponent: 0, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: LoopingMinutePicker
        init(_ p: LoopingMinutePicker) { parent = p }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

        func pickerView(_ pickerView: UIPickerView,
                        numberOfRowsInComponent component: Int) -> Int {
            LoopingMinutePicker.rowCount
        }

        func pickerView(_ pickerView: UIPickerView,
                        viewForRow row: Int,
                        forComponent component: Int,
                        reusing view: UIView?) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            label.text          = String(format: "%02d", row % 60)
            label.textColor     = .white
            label.textAlignment = .center
            label.font          = .systemFont(ofSize: 20, weight: .regular)
            return label
        }

        func pickerView(_ pickerView: UIPickerView,
                        didSelectRow row: Int,
                        inComponent component: Int) {
            parent.selection = row % 60
        }
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
    let hourRange: ClosedRange<Int>

    init(
        value: Binding<TimeValue>,
        autoLabel: String,
        hourRange: ClosedRange<Int> = 0...5
    ) {
        self._value = value
        self.autoLabel = autoLabel
        self.hourRange = hourRange
    }

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

            // Hours + minutes scroll pickers
            if !value.auto {
                HStack(spacing: 0) {
                    Spacer()

                    // Hours wheel
                    VStack(spacing: 4) {
                        Text("HOURS")
                            .font(.custom("DM Sans", size: 11))
                            .foregroundColor(Color.white.opacity(0.3))
                            .kerning(1)
                        Picker("", selection: $value.hours) {
                            ForEach(Array(hourRange), id: \.self) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80, height: 120)
                        .clipped()
                        .colorScheme(.dark)
                    }

                    // Colon separator
                    Text(":")
                        .font(.libreFranklin(size: 32))
                        .foregroundColor(Color.white.opacity(0.2))
                        .padding(.top, 22)
                        .padding(.horizontal, 6)

                    // Minutes wheel — 1-minute increments, loops 59 → 00
                    VStack(spacing: 4) {
                        Text("MINUTES")
                            .font(.custom("DM Sans", size: 11))
                            .foregroundColor(Color.white.opacity(0.3))
                            .kerning(1)
                        LoopingMinutePicker(selection: $value.minutes)
                            .frame(width: 80, height: 120)
                            .clipped()
                    }

                    Spacer()
                }
                .padding(.top, 12)
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

        @State private var step      = 0
        @State private var saving    = false
        @State private var saveError: String? = nil
        @State private var answers   = SurveyAnswers()
        @State private var birthdayDate: Date = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: "2000-01-01")
                ?? Calendar.current.date(byAdding: .year, value: -25, to: Date())
                ?? Date()
        }()
        // Long-routine warning alert
        @State private var showLongRoutineAlert = false
        @State private var longRoutineTimeLabel = ""

        // Location permission explanation alert
        @State private var showLocationPermissionAlert = false
        @State private var locationStatusAfterPrompt: CLAuthorizationStatus = .notDetermined
        @State private var pendingFinishSnapshot: SurveyAnswers? = nil

        // WHOOP integration state
        @State private var whoopSelected: Bool = false
        @State private var whoopLoading: Bool = false
        @State private var whoopRecommendedHours: Double? = nil
        @State private var whoopError: String? = nil
        // Oura integration state
        @State private var ouraSelected: Bool = false
        @State private var ouraLoading: Bool = false
        @State private var ouraRecommendedHours: Double? = nil
        @State private var ouraError: String? = nil
        
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
            case 0: return !answers.age.isEmpty
            case 1: return answers.lifestyle != nil
            case 2: return !answers.wakeDays.isEmpty
            case 3: return answers.calendar  != nil
            case 4: // sleep step — wearable selected must complete its fetch before continuing
                if whoopSelected { return whoopRecommendedHours != nil }
                if ouraSelected  { return ouraRecommendedHours  != nil }
                return true
            case 6: // commute step — only requires a transport mode selection
                return !answers.commuteMode.isEmpty
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
                                checkRoutineBeforeContinue()
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

                            // ── Wearable cards (sleep step only) ─
                            if step == 4 {
                                sleepWearableCards
                            }
                        }
                        .frame(maxWidth: 480)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        // ── Location permission explanation alert ─────────────────
        // Shown when the user chose something other than "Always Allow"
        // after the system location prompt at the end of onboarding.
        .alert("Location Access Needed", isPresented: $showLocationPermissionAlert) {
            if locationStatusAfterPrompt == .authorizedWhenInUse {
                // Status is When In Use — iOS can still show the native upgrade
                // dialog ("Change to Always Allow?") via a second request.
                Button("Allow Always") {
                    Task { await retryAlwaysAuthorization() }
                }
            } else {
                // Status is Denied — only Settings can change it.
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    if let snapshot = pendingFinishSnapshot { onFinish?(snapshot) }
                }
            }
            Button("Continue Without", role: .cancel) {
                if let snapshot = pendingFinishSnapshot { onFinish?(snapshot) }
            }
        } message: {
            if locationStatusAfterPrompt == .authorizedWhenInUse {
                Text("Lunifer needs \"Always\" location access to calculate your commute time even when the app is in the background. Without it, your alarm may not reflect real-time traffic. Tap \"Allow Always\" to update your preference.")
            } else {
                Text("Lunifer needs \"Always\" location access to accurately calculate your commute, even when running in the background. You can enable this in Settings under Location → Always.")
            }
        }
        // ── Long routine warning alert ────────────────────────────
        .alert("Long Morning Routine", isPresented: $showLongRoutineAlert) {
            Button("Yes") {
                // User confirmed — proceed with the original action
                isLastStep ? handleFinish() : advance()
            }
            Button("No", role: .cancel) {
                answers.routine = TimeValue(hours: 1, minutes: 0, auto: false)
            }
        } message: {
            Text("\(longRoutineTimeLabel) is a long time for a morning routine. Are you sure that's how long you want Lunifer to remember your morning routine?")
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
        
        // Step 0 — Birthday Question
        private var stepAge: some View {
            VStack(spacing: 0) {
                Text("When's your birthday?")
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

                    DatePicker(
                        "",
                        selection: $birthdayDate,
                        in: ...Calendar.current.date(byAdding: .year, value: -13, to: Date())!,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .frame(height: 160)
                    .clipped()
                    .onChange(of: birthdayDate) { _, newDate in
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        answers.age = formatter.string(from: newDate)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .padding(.bottom, 24)
            }
            .onAppear {
                // Sync answers.age → birthdayDate on first render, so any
                // pre-loaded survey answer is reflected in the picker.
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                if let date = formatter.date(from: answers.age) {
                    birthdayDate = date
                }
                // Write the picker's current date into answers.age so
                // canNext passes even if the user never moves the wheel.
                answers.age = formatter.string(from: birthdayDate)
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
                Text("How many hours do you need to feel well rested?")
                    .font(.custom("Cormorant Garamond", size: 22))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 25)
                    .padding(.bottom, 16)

                // ── Manual / Lunifer-learn picker ───────────────
                // Hidden when a wearable is selected and data is fetched
                if (!whoopSelected && !ouraSelected) || whoopError != nil || ouraError != nil {
                    TimeScalePicker(value: $answers.sleep,
                                    autoLabel: "I'm not sure — let Lunifer learn this",
                                    hourRange: 0...12)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 40)
                    // Deselect any wearable if the user starts interacting with manual picker
                    .onChange(of: answers.sleep.hours)   { _, _ in
                        if whoopSelected && whoopRecommendedHours == nil { whoopSelected = false }
                        if ouraSelected  && ouraRecommendedHours  == nil { ouraSelected  = false }
                    }
                    .onChange(of: answers.sleep.minutes) { _, _ in
                        if whoopSelected && whoopRecommendedHours == nil { whoopSelected = false }
                        if ouraSelected  && ouraRecommendedHours  == nil { ouraSelected  = false }
                    }
                    .onChange(of: answers.sleep.auto)    { _, _ in
                        if whoopSelected && whoopRecommendedHours == nil { whoopSelected = false }
                        if ouraSelected  && ouraRecommendedHours  == nil { ouraSelected  = false }
                    }
                } else {
                    Spacer().frame(height: 24)
                }
            }
        }

        // ── Wearable cards for sleep step (rendered below nav buttons) ──
        @ViewBuilder
        private var sleepWearableCards: some View {
            // ── "or" divider ────────────────────────────────────
            HStack(spacing: 12) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                Text("or let your wearable decide")
                    .font(.custom("DM Sans", size: 12))
                    .foregroundColor(Color.white.opacity(0.25))
                    .fixedSize()
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)

            // ── WHOOP card ──────────────────────────────────────
            OptionCard(isSelected: whoopSelected) {
                if !whoopSelected {
                    whoopSelected = true
                    ouraSelected  = false
                    ouraRecommendedHours = nil
                    ouraError = nil
                    Task { await connectWhoop() }
                }
            } content: {
                ZStack {
                    HStack(spacing: 8) {
                        Image("WhoopLogo")
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Let my WHOOP decide")
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(whoopSelected
                                                 ? Color.white.opacity(0.95)
                                                 : Color.white.opacity(0.7))

                            if whoopLoading {
                                Text("Connecting to WHOOP…")
                                    .font(.custom("DM Sans", size: 12))
                                    .foregroundColor(Color.white.opacity(0.4))
                            } else if let hours = whoopRecommendedHours {
                                Text("Tonight: \(SleepDurationModel.formatted(hours))")
                                    .font(.custom("DM Sans", size: 12))
                                    .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.85))
                            } else if let error = whoopError {
                                Text(error)
                                    .font(.custom("DM Sans", size: 12))
                                    .foregroundColor(Color(red: 1, green: 0.392, blue: 0.392).opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    HStack {
                        Spacer()
                        if whoopLoading {
                            ProgressView().tint(Color.white.opacity(0.5)).scaleEffect(0.85)
                        } else if whoopRecommendedHours != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.5))
                                .font(.system(size: 16))
                        } else if whoopSelected && whoopError != nil {
                            Button {
                                whoopError = nil
                                Task { await connectWhoop() }
                            } label: {
                                Text("Retry")
                                    .font(.custom("DM Sans", size: 12))
                                    .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 35)

            // ── Oura Ring card ──────────────────────────────────
            OptionCard(isSelected: ouraSelected) {
                if !ouraSelected {
                    ouraSelected  = true
                    whoopSelected = false
                    whoopRecommendedHours = nil
                    whoopError = nil
                    Task { await connectOura() }
                }
            } content: {
                ZStack {
                    HStack(spacing: 8) {
                        Image("OuraLogo")
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Let my Oura Ring decide")
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(ouraSelected
                                                 ? Color.white.opacity(0.95)
                                                 : Color.white.opacity(0.7))

                            if ouraLoading {
                                Text("Connecting to Oura…")
                                    .font(.custom("DM Sans", size: 12))
                                    .foregroundColor(Color.white.opacity(0.4))
                            } else if let hours = ouraRecommendedHours {
                                Text("Tonight: \(SleepDurationModel.formatted(hours))")
                                    .font(.custom("DM Sans", size: 12))
                                    .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.85))
                            } else if let error = ouraError {
                                Text(error)
                                    .font(.custom("DM Sans", size: 12))
                                    .foregroundColor(Color(red: 1, green: 0.392, blue: 0.392).opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    HStack {
                        Spacer()
                        if ouraLoading {
                            ProgressView().tint(Color.white.opacity(0.5)).scaleEffect(0.85)
                        } else if ouraRecommendedHours != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.5))
                                .font(.system(size: 16))
                        } else if ouraSelected && ouraError != nil {
                            Button {
                                ouraError = nil
                                Task { await connectOura() }
                            } label: {
                                Text("Retry")
                                    .font(.custom("DM Sans", size: 12))
                                    .foregroundColor(Color(red: 0.627, green: 0.471, blue: 1.0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 35)
        }

        // Step 5 — Morning routine
        private var stepRoutine: some View {
            VStack(alignment: .center, spacing: 0) {
                Text("How long is your morning routine?")
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
        
        // Step 6 — Commute mode (student / commuter only)
        // Duration is no longer asked — CommuteManager calculates it live via
        // MKDirections and falls back to 30 minutes when routing is unavailable.
        private var stepCommute: some View {
            VStack(alignment: .center, spacing: 0) {
                Text("How do you commute?")
                    .font(.custom("Cormorant Garamond", size: 22))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)

                Text("Lunifer will calculate your commute time automatically.")
                    .font(.custom("DM Sans", size: 13))
                    .fontWeight(.light)
                    .foregroundColor(Color.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 20)
                    .padding(.horizontal, 40)

                // ── Transport mode icons ─────────────────────
                HStack(spacing: 0) {
                    ForEach([
                        ("drive",   "car.fill"),
                        ("transit", "tram.fill"),
                        ("walk",    "figure.walk"),
                        ("bike",    "bicycle")
                    ], id: \.0) { mode, icon in
                        let selected = answers.commuteMode == mode
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                answers.commuteMode = mode
                            }
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(selected
                                    ? Color.white.opacity(0.95)
                                    : Color.white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(selected
                                            ? Color(red: 0.627, green: 0.471, blue: 1.0).opacity(0.25)
                                            : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 14)

                if answers.commuteMode.isEmpty {
                    Text("Select a commute type above to continue.")
                        .font(.custom("DM Sans", size: 13))
                        .foregroundColor(Color.white.opacity(0.35))
                        .padding(.top, 4)
                        .padding(.horizontal, 40)
                        .transition(.opacity)
                }

                Spacer().frame(height: 24)
            }
        }
        
        // ── MARK: Navigation ─────────────────────────────────────

        /// Called by the primary button. Intercepts the routine step so the
        /// long-routine warning fires on "Done" rather than mid-scroll.
        private func checkRoutineBeforeContinue() {
            if step == 5 && showRoutine && !answers.routine.auto && answers.routine.hours > 4 {
                let h = answers.routine.hours
                let m = answers.routine.minutes
                longRoutineTimeLabel = m > 0 ? "\(h) hours \(m) minutes" : "\(h) hours"
                showLongRoutineAlert = true
                return
            }
            isLastStep ? handleFinish() : advance()
        }

        private func advance() {
            // Request CoreMotion permission as the user leaves the sleep step.
            // There is no explicit requestAuthorization() for CoreMotion — iOS shows
            // the "Motion & Fitness" prompt the first time startActivityUpdates is called.
            // We start updates briefly here just to surface the prompt, then stop.
            if step == 4 && CMMotionActivityManager.authorizationStatus() == .notDetermined {
                Task {
                    let m = CMMotionActivityManager()
                    m.startActivityUpdates(to: .main) { _ in }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    m.stopActivityUpdates()
                }
            }
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

        // MARK: - WHOOP

        @MainActor
        private func connectWhoop() async {
            whoopLoading = true
            whoopError   = nil
            do {
                let manager = WhoopManager.shared
                // If already connected, just refresh sleep need
                if manager.isConnected {
                    try await manager.fetchSleepNeed()
                } else {
                    try await manager.connect()
                }
                whoopRecommendedHours = manager.recommendedSleepHours
                // Store into answers so the value flows into the alarm calculation
                // We use hours/minutes with auto=false so SleepInsights picks it up too
                let h = Int(manager.recommendedSleepHours)
                let m = Int((manager.recommendedSleepHours - Double(h)) * 60)
                answers.sleep = TimeValue(hours: h, minutes: m, auto: false)
            } catch WhoopError.cancelled {
                // User closed the sheet — silently deselect WHOOP
                whoopSelected = false
            } catch {
                whoopError = error.localizedDescription
            }
            whoopLoading = false
        }

        // MARK: - Oura

        @MainActor
        private func connectOura() async {
            ouraLoading = true
            ouraError   = nil
            do {
                let manager = OuraManager.shared
                if manager.isConnected {
                    try await manager.fetchSleepRecommendation()
                } else {
                    try await manager.connect()
                }
                ouraRecommendedHours = manager.recommendedSleepHours
                let h = Int(manager.recommendedSleepHours)
                let m = Int((manager.recommendedSleepHours - Double(h)) * 60)
                answers.sleep = TimeValue(hours: h, minutes: m, auto: false)
            } catch OuraError.cancelled {
                ouraSelected = false
            } catch {
                ouraError = error.localizedDescription
            }
            ouraLoading = false
        }

        // ── MARK: Location permission retry ─────────────────────
        // Called when the user taps "Allow Always" in the explanation alert.
        // At this point status is .authorizedWhenInUse, so iOS will show the
        // native "Change to Always Allow?" upgrade dialog.

        @MainActor
        private func retryAlwaysAuthorization() async {
            let status = await LocationManager.shared.requestAlwaysAuthorizationAsync()
            if status == .authorizedAlways {
                // User upgraded — proceed to dashboard.
                if let snapshot = pendingFinishSnapshot { onFinish?(snapshot) }
            } else {
                // Still not Always — show the alert again with updated status.
                locationStatusAfterPrompt = status
                showLocationPermissionAlert = true
            }
        }

        // ── MARK: Firestore save ─────────────────────────────────
        // Mirrors handleFinish() in luniferSurvey.jsx exactly
        
        private func handleFinish() {
            guard Auth.auth().currentUser?.uid != nil else {
                saveError = "Not signed in. Please sign in and try again."
                return
            }
            // Always persist commute as auto-mode with the 30-min cold-start default.
            // CommuteManager provides live MKDirections durations at runtime;
            // the stored hours/minutes values are only used as a fallback when
            // routing is unavailable.
            if showCommute {
                answers.commute = TimeValue(hours: 0, minutes: 30, auto: true)
            }
            let snapshot = answers
            Task { @MainActor in
                saving    = true
                saveError = nil

                // Save locally first — this always succeeds and lets the user proceed.
                snapshot.saveToDefaults()
                surveyCompleted = true

                // Fire the Firestore sync in the background. A failure here is
                // non-fatal: the local copy is the source of truth on this device,
                // and syncProfile() will push it again whenever the user edits
                // settings. Log the error so it's visible in the Xcode console.
                Task {
                    do {
                        try await SurveyAnswersStore.shared.saveInitialProfile(snapshot)
                        print("✅ Initial profile synced to Firestore")
                    } catch {
                        print("⚠️ Firestore sync failed (non-fatal): \(error)")
                    }
                }

                await LuniferAlarm.shared.requestAuthorization()

                // Request standard notification permission (UNUserNotificationCenter).
                // This is separate from AlarmKit authorization and is required for
                // WakeNotification, BatteryAlarmNotification, CommuteNotification,
                // and RestDayEventNotification. Without this, all four are silently skipped.
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])

                // Request location access for commuters/students so CommuteManager
                // can perform live MKDirections routing. We await the user's response
                // so we can detect if they chose something other than "Always Allow"
                // and explain why the fuller permission is needed before proceeding.
                if snapshot.lifestyle == "student" || snapshot.lifestyle == "commuter" {
                    let status = await LocationManager.shared.requestAlwaysAuthorizationAsync()
                    if status != .authorizedAlways {
                        // Hold onFinish — show explanation alert first.
                        // The alert buttons call onFinish when the user responds.
                        locationStatusAfterPrompt = status
                        pendingFinishSnapshot = snapshot
                        showLocationPermissionAlert = true
                        saving = false
                        return
                    }
                }

                onFinish?(snapshot)
                saving = false
            }
        }
    }
    
// ── MARK: Preview ────────────────────────────────────────────

#Preview {
    LuniferSurvey()
        .environmentObject(CalendarManager())
}
