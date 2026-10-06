import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import CoreMotion
import UIKit
import UserNotifications
import AVFoundation

// ── MARK: Models ─────────────────────────────────────────────

struct TimeValue: Codable, Equatable {
    var hours: Int
    var minutes: Int
    var auto: Bool
}

struct SurveyAnswers: Codable {
    var age: String        = "2000-01-01"
    var wakeDays: [String] = ["mon", "tue", "wed", "thu", "fri"]
    var calendar: String?  = nil
    var sleep   = TimeValue(hours: 8, minutes: 0,  auto: false)
    var routine = TimeValue(hours: 0, minutes: 45, auto: false)
    var commute = TimeValue(hours: 0, minutes: 0, auto: true)
    /// Transport mode for commute: "drive", "transit", "walk", or "bike"
    var commuteMode: String = "drive"

    var hasCommuteSetup: Bool {
        !commuteMode.isEmpty
    }

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

// ── MARK: Option card ────────────────────────────────────────

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

// ── MARK: Combined hours + minutes picker ────────────────────
// A single UIPickerView with two components (hours left, minutes right).
// Using one UIPickerView means UIKit owns all gesture routing internally,
// which prevents touch-target offset bugs that arise when two separate
// UIViewRepresentable pickers sit side-by-side in a SwiftUI HStack.
// Minutes use 60 000 virtual rows so the wheel loops seamlessly.

private struct HoursMinutesPicker: UIViewRepresentable {
    @Binding var hours: Int
    @Binding var minutes: Int
    let hourRange: ClosedRange<Int>
    let maxTotalMinutes: Int?

    private static let minuteRowCount = 60_000
    private static let minuteMidStart = minuteRowCount / 2  // 30 000 % 60 == 0 → maps to :00

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate   = context.coordinator
        picker.backgroundColor = .clear
        clampSelection()
        picker.selectRow(hours - hourRange.lowerBound, inComponent: 0, animated: false)
        picker.selectRow(Self.minuteMidStart + minutes,  inComponent: 1, animated: false)
        return picker
    }

    func updateUIView(_ uiView: UIPickerView, context: Context) {
        clampSelection()
        let expectedHourRow = hours - hourRange.lowerBound
        if uiView.selectedRow(inComponent: 0) != expectedHourRow {
            uiView.selectRow(expectedHourRow, inComponent: 0, animated: true)
        }
        let currentMinRow = uiView.selectedRow(inComponent: 1)
        if currentMinRow % 60 != minutes {
            uiView.selectRow(Self.minuteMidStart + minutes, inComponent: 1, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func clampedMinutes(hours: Int, minutes: Int) -> (hours: Int, minutes: Int) {
        let hour = min(max(hours, hourRange.lowerBound), hourRange.upperBound)
        guard let maxTotalMinutes else {
            return (hour, min(max(minutes, 0), 59))
        }
        let total = min(max(hour * 60 + minutes, 0), maxTotalMinutes)
        return (total / 60, total % 60)
    }

    private func clampSelection() {
        let clamped = clampedMinutes(hours: hours, minutes: minutes)
        if hours != clamped.hours { hours = clamped.hours }
        if minutes != clamped.minutes { minutes = clamped.minutes }
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: HoursMinutesPicker
        init(_ p: HoursMinutesPicker) { parent = p }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }

        func pickerView(_ pickerView: UIPickerView,
                        numberOfRowsInComponent component: Int) -> Int {
            component == 0 ? parent.hourRange.count : HoursMinutesPicker.minuteRowCount
        }

        func pickerView(_ pickerView: UIPickerView,
                        viewForRow row: Int,
                        forComponent component: Int,
                        reusing view: UIView?) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            label.textColor     = .white
            label.textAlignment = .center
            label.font          = .systemFont(ofSize: 20, weight: .regular)
            label.text = component == 0
                ? String(format: "%02d", row + parent.hourRange.lowerBound)
                : String(format: "%02d", row % 60)
            return label
        }

        func pickerView(_ pickerView: UIPickerView,
                        didSelectRow row: Int,
                        inComponent component: Int) {
            if component == 0 {
                let selectedHours = row + parent.hourRange.lowerBound
                let selectedMinutes = parent.minutes
                let clamped = parent.clampedMinutes(hours: selectedHours, minutes: selectedMinutes)
                parent.hours = clamped.hours
                parent.minutes = clamped.minutes
                if clamped.hours != selectedHours {
                    pickerView.selectRow(clamped.hours - parent.hourRange.lowerBound, inComponent: 0, animated: true)
                }
                if clamped.minutes != selectedMinutes {
                    pickerView.selectRow(HoursMinutesPicker.minuteMidStart + clamped.minutes, inComponent: 1, animated: true)
                }
            } else {
                let selectedMinutes = row % 60
                let clamped = parent.clampedMinutes(hours: parent.hours, minutes: selectedMinutes)
                parent.hours = clamped.hours
                parent.minutes = clamped.minutes
                if clamped.minutes != selectedMinutes {
                    pickerView.selectRow(HoursMinutesPicker.minuteMidStart + clamped.minutes, inComponent: 1, animated: true)
                }
            }
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
    let maxTotalMinutes: Int?
    /// When false, the "let Lunifer figure this out" auto toggle is hidden and
    /// the hours/minutes wheels are always shown. Used by the morning-routine
    /// picker, which is manual-only (Lunifer does not learn routine duration).
    let showAutoToggle: Bool

    init(
        value: Binding<TimeValue>,
        autoLabel: String,
        hourRange: ClosedRange<Int> = 0...5,
        maxTotalMinutes: Int? = nil,
        showAutoToggle: Bool = true
    ) {
        self._value = value
        self.autoLabel = autoLabel
        self.hourRange = hourRange
        self.maxTotalMinutes = maxTotalMinutes
        self.showAutoToggle = showAutoToggle
    }

    var body: some View {
        VStack(spacing: 0) {

            // Auto toggle — mirrors the .auto-toggle div in React
            if showAutoToggle {
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
            }

            // Hours + minutes scroll pickers (single UIPickerView, two components)
            if !value.auto || !showAutoToggle {
                VStack(spacing: 16) {
                    // Column headers — spacers mirror the two equal components
                    HStack(spacing: 0) {
                        Spacer()
                        Text("HOURS")
                            .font(.custom("DM Sans", size: 11))
                            .foregroundColor(Color.white.opacity(0.3))
                            .kerning(1)
                        Spacer()
                        Text("MINUTES")
                            .font(.custom("DM Sans", size: 11))
                            .foregroundColor(Color.white.opacity(0.3))
                            .kerning(1)
                        Spacer()
                    }

                    // Combined picker with colon overlaid between the two components
                    ZStack {
                        HoursMinutesPicker(hours: $value.hours,
                                           minutes: $value.minutes,
                                           hourRange: hourRange,
                                           maxTotalMinutes: maxTotalMinutes)
                            .frame(height: 120)

                        Text(":")
                            .font(.libreFranklin(size: 32))
                            .foregroundColor(Color.white.opacity(0.2))
                    }
                    .frame(height: 120)
                    .clipped()
                    // Nudge the wheel down so its top rows don't overlap the
                    // "HOURS" / "MINUTES" column headers above it.
                    .padding(.top, 10)
                }
                .padding(.top, 12)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: value.auto)
        .onAppear {
            // Routine no longer offers an auto/learn option. When the toggle is
            // hidden, force a concrete manual value so downstream alarm math uses
            // the entered duration rather than the 60-minute auto fallback —
            // this also migrates any legacy answers that stored auto == true.
            if !showAutoToggle && value.auto { value.auto = false }
            clampToMaximumIfNeeded()
        }
        .onChange(of: value.hours) { _, _ in
            clampToMaximumIfNeeded()
        }
        .onChange(of: value.minutes) { _, _ in
            clampToMaximumIfNeeded()
        }
    }

    private func clampToMaximumIfNeeded() {
        guard let maxTotalMinutes else { return }
        let total = value.hours * 60 + value.minutes
        guard total > maxTotalMinutes else { return }
        value.hours = maxTotalMinutes / 60
        value.minutes = maxTotalMinutes % 60
    }
}

// ── MARK: LuniferSurvey ──────────────────────────────────────

struct LuniferSurvey: View {
        var preSelectedCalendar: String = ""
        var onFinish: ((SurveyAnswers) -> Void)? = nil
        @AppStorage("surveyCompleted") private var surveyCompleted = false

        /// True when the user already chose their calendar on the pre-auth screen,
        /// so step 3 (calendar) can be skipped entirely in the survey.
        private var skipCalendarStep: Bool { !preSelectedCalendar.isEmpty }

        /// Maps the raw step index to a visual index for the progress dots,
        /// accounting for the skipped calendar step.
        private var visualStep: Int {
            var visual = step - 2
            if skipCalendarStep && step > 3 { visual -= 1 }
            return max(visual, 0)
        }

        @EnvironmentObject private var calendarManager: CalendarManager
        @Environment(\.openURL) private var openURL

        @State private var step      = 2
        @State private var saving    = false
        @State private var saveError: String? = nil
        @State private var answers   = SurveyAnswers()
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
        // Calendar nudge
        @State private var showCalendarNudge = false
        
        private var totalSteps: Int {
            skipCalendarStep ? 3 : 4
        }
        private var isLastStep: Bool { visualStep == totalSteps - 1 }
        
        private var canNext: Bool {
            switch step {
            case 2: return !answers.wakeDays.isEmpty
            case 3: return answers.calendar  != nil
            case 4: // sleep step — wearable selected must complete its fetch before continuing
                if whoopSelected { return whoopRecommendedHours != nil }
                if ouraSelected  { return ouraRecommendedHours  != nil }
                return true
            default: return true
            }
        }
        
        var body: some View {
            ZStack {
                LuniferBackground()

                ScrollView {
                        VStack(spacing: 0) {
                            
                            SurveyStepDots(total: totalSteps, current: visualStep)
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
                            if visualStep > 0 {
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

                // ── Calendar nudge notification pop-up ───────────────
                if showCalendarNudge {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    VStack(spacing: 0) {
                        // Body
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Are you sure you don't want to allow access to your calendar?")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(.label))
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Lunifer works best when it can read your schedule — connecting a calendar lets it set your alarm around your actual day.")
                                .font(.system(size: 13))
                                .foregroundColor(Color(.secondaryLabel))
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(3)
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                        Divider()

                        // Action buttons
                        HStack(spacing: 0) {
                            Button {
                                showCalendarNudge = false
                                advance()
                            } label: {
                                Text("Yes, Continue")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color(.systemRed))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }

                            Divider().frame(height: 44)

                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showCalendarNudge = false
                                    answers.calendar = nil
                                }
                            } label: {
                                Text("No")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color(.systemBlue))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }
                        }
                    }
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 8)
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 20)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        // ── Pre-selected calendar (chosen before sign-in) ─────────
        // If the user picked a calendar on the CalendarChoiceScreen,
        // set answers.calendar immediately and trigger the service
        // connection that the calendar step would have triggered.
        .onAppear {
            guard skipCalendarStep else { return }
            answers.calendar = preSelectedCalendar
            switch preSelectedCalendar {
            case "apple":
                if calendarManager.authorizationStatus == .notDetermined {
                    Task { await calendarManager.requestAccess() }
                }
            case "google":
                if !GoogleCalendarService.shared.isConnected() {
                    Task { await GoogleCalendarService.shared.connect() }
                }
            case "outlook":
                if !MicrosoftCalendarService.shared.isConnected() {
                    Task { await MicrosoftCalendarService.shared.connect() }
                }
            default:
                break
            }
        }
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
                answers.routine = TimeValue(hours: 0, minutes: 45, auto: false)
            }
        } message: {
            Text("\(longRoutineTimeLabel) is a long time for a morning routine. Are you sure that's how long you want Lunifer to remember your morning routine?")
        }
        }

        // ── MARK: Step content ───────────────────────────────────
        
        @ViewBuilder
        private var stepContent: some View {
            switch step {
            case 2: stepWakeDays
            case 3: stepCalendar
            case 4: stepSleep
            case 5: stepRoutine
            default: EmptyView()
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
                Text("What days of the week should Lunifer wake you up?")
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

                Text("Lunifer will sync with your calendar to automatically adapt your alarm around your schedule.")
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
                .padding(.horizontal, 60)
            }
        }
        
        @ViewBuilder
        private func calendarCard<Icon: View>(id: String, name: String, @ViewBuilder icon: () -> Icon) -> some View {
            let iconView = icon()
            OptionCard(isSelected: answers.calendar == id) {
                answers.calendar = id
                if id == "none" {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showCalendarNudge = true
                    }
                } else {
                    showCalendarNudge = false
                    // Trigger consent for the chosen provider. Apple uses EventKit;
                    // Google/Outlook read their web APIs directly so they work even
                    // when the account isn't synced into the iOS system calendar.
                    switch id {
                    case "apple":
                        if calendarManager.authorizationStatus == .notDetermined {
                            Task { await calendarManager.requestAccess() }
                        }
                    case "google":
                        if !GoogleCalendarService.shared.isConnected() {
                            Task { await GoogleCalendarService.shared.connect() }
                        }
                    case "outlook":
                        if !MicrosoftCalendarService.shared.isConnected() {
                            Task { await MicrosoftCalendarService.shared.connect() }
                        }
                    default:
                        break
                    }
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
                Text("How much sleep do you need?")
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
                                    autoLabel: "Let Lunifer figure this out",
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
                                autoLabel: "Not sure — let Lunifer figure this out",
                                hourRange: 0...3,
                                maxTotalMinutes: 180,
                                showAutoToggle: false)
                .padding(.bottom, 24)
                .padding(.horizontal, 40)
            }
        }
        // ── MARK: Navigation ─────────────────────────────────────

        /// Called by the primary button. Intercepts the routine step so the
        /// long-routine warning fires on "Done" rather than mid-scroll.
        private func checkRoutineBeforeContinue() {
            if step == 5 && !answers.routine.auto && routineMinutes > 90 {
                let h = answers.routine.hours
                let m = answers.routine.minutes
                longRoutineTimeLabel = m > 0 ? "\(h) hours \(m) minutes" : "\(h) hours"
                showLongRoutineAlert = true
                return
            }
            isLastStep ? handleFinish() : advance()
        }

        private var routineMinutes: Int {
            answers.routine.hours * 60 + answers.routine.minutes
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
                    requestMicrophonePermission()
                }
            }
            if skipCalendarStep && step == 2 {
                // Skip the calendar step when it was pre-selected before sign-in.
                step = 4
            } else {
                step += 1
            }
        }

        private func goBack() {
            if step > 0 {
                // Skip back over the calendar step when it was pre-selected
                if skipCalendarStep && step == 4 {
                    step = 2
                } else if step == 2 {
                    return
                } else {
                    step -= 1
                }
            }
        }

        private func requestMicrophonePermission() {
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { _ in }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { _ in }
            }
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
        
        private func handleFinish() {
            guard Auth.auth().currentUser?.uid != nil else {
                saveError = "Not signed in. Please sign in and try again."
                return
            }
            // Always persist commute as auto-mode with a zero fallback.
            // CommuteManager adds travel time only when it can route to a
            // calendar event location.
            answers.commute = TimeValue(hours: 0, minutes: 0, auto: true)
            if answers.commuteMode.isEmpty {
                answers.commuteMode = "drive"
            }
            let snapshot = answers
            Task { @MainActor in
                saving    = true
                saveError = nil

                // Save locally first — this always succeeds and lets the user proceed.
                snapshot.saveToDefaults()
                surveyCompleted = true

                // Reset the one-time coach-mark walkthrough flag on fresh onboarding so
                // a newly onboarded user (including a new account on a device where a
                // previous user already finished the tour) sees it. Tying this to survey
                // completion — rather than to sign-out — means a returning user signing
                // back in never re-triggers the walkthrough.
                UserDefaults.standard.set(false, forKey: AppPreferencesStore.Keys.hasSeenWalkthrough)

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

                // Request location access for everyone configuring a commute so CommuteManager
                // can perform live MKDirections routing. We await the user's response
                // so we can detect if they chose something other than "Always Allow"
                // and explain why the fuller permission is needed before proceeding.
                if snapshot.hasCommuteSetup {
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
    
// ── MARK: Commute preview card ───────────────────────────────
// The dashboard commute card as it appears once the user has locations on
// their calendar events.
// the payoff during onboarding. The map is a baked sample route (there is no
// real event yet) rendered through the same snapshotter as the live card; the
// duration/leave-by are representative walking sample values. The selectable
// commute mode above remains independent from this illustrative preview.

private struct CommutePreviewCard: View {
    let mode: String

    private var modeIcon: String {
        switch mode {
        case "transit": return "train.side.front.car"
        case "walk":    return "figure.walk"
        case "bike":    return "bicycle"
        default:        return "car.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COMMUTE")
                .font(.custom("DM Sans", size: 9))
                .kerning(2)
                .foregroundColor(Color.white.opacity(0.3))

            CommuteRouteMap(source: .sample, height: 150)

            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: modeIcon)
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(Color(red: 0.706, green: 0.588, blue: 0.902))
                    (
                        Text("\(CommuteRouteSample.durationMinutes) min")
                            .font(.libreFranklin(size: 22))
                            .foregroundColor(Color.white.opacity(0.85))
                        + Text(" to \(CommuteRouteSample.destinationName)")
                            .font(.libreFranklin(size: 22))
                            .foregroundColor(Color.white.opacity(0.55))
                    )
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Text("Leave by 7:38 AM")
                    .font(.custom("DM Sans", size: 12))
                    .foregroundColor(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// ── MARK: Preview ────────────────────────────────────────────

#Preview {
    LuniferSurvey()
        .environmentObject(CalendarManager())
}
