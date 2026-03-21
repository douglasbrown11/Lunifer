import SwiftUI
import FirebaseAuth
import AVFoundation

// ── MARK: Dashboard ──────────────────────────────────────────

struct LuniferDashboard: View {
    @Binding var answers: SurveyAnswers
    @State private var showSettings = false
    @State private var showSound = false
    @State private var alarmExpanded = false
    @State private var overrideTime = Date()
    @State private var overrideActive = false
    @AppStorage("luniferEnabled") private var luniferEnabled: Bool = true
    @AppStorage("selectedAlarmSound") private var selectedAlarmSound: String = "DeafultAlarm.wav"

    private var wakeUpTime: String { // calculate wakeup time based off of survey questions
        if overrideActive {
            let f = DateFormatter()
            f.dateFormat = "h:mm"
            return f.string(from: overrideTime)
        }
        let targetMinutes = 9 * 60
        let routineMinutes = answers.routine.auto
            ? 60
            : answers.routine.hours * 60 + answers.routine.minutes
        let commuteMinutes: Int
        if answers.lifestyle == "student" || answers.lifestyle == "commuter" {
            commuteMinutes = answers.commute.auto ? 30 : answers.commute.hours * 60 + answers.commute.minutes
        } else {
            commuteMinutes = 0
        }
        let wakeMinutes = ((targetMinutes - routineMinutes - commuteMinutes) % (24 * 60) + 24 * 60) % (24 * 60)
        let hour    = wakeMinutes / 60
        let minute  = wakeMinutes % 60
        let display = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return String(format: "%d:%02d", display, minute)
    }

    //__________________________________________________________________________________________________________
    private var wakeUpPeriod: String {
        if overrideActive {
            let f = DateFormatter()
            f.dateFormat = "a"
            return f.string(from: overrideTime)
        }
        let targetMinutes = 9 * 60
        let routineMinutes = answers.routine.auto
            ? 60
            : answers.routine.hours * 60 + answers.routine.minutes
        let commuteMinutes: Int
        if answers.lifestyle == "student" || answers.lifestyle == "commuter" {
            commuteMinutes = answers.commute.auto ? 30 : answers.commute.hours * 60 + answers.commute.minutes
        } else {
            commuteMinutes = 0
        }
        let wakeMinutes = ((targetMinutes - routineMinutes - commuteMinutes) % (24 * 60) + 24 * 60) % (24 * 60)
        let hour = wakeMinutes / 60
        return hour >= 12 ? "PM" : "AM"
    }

    private var calculatedAlarmDate: Date {
        let targetMinutes = 9 * 60
        let routineMinutes = answers.routine.auto
            ? 60
            : answers.routine.hours * 60 + answers.routine.minutes
        let commuteMinutes: Int
        if answers.lifestyle == "student" || answers.lifestyle == "commuter" {
            commuteMinutes = answers.commute.auto ? 30 : answers.commute.hours * 60 + answers.commute.minutes
        } else {
            commuteMinutes = 0
        }
        let wakeMinutes = ((targetMinutes - routineMinutes - commuteMinutes) % (24 * 60) + 24 * 60) % (24 * 60)
        let hour   = wakeMinutes / 60
        let minute = wakeMinutes % 60
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour   = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private var tomorrowDateString: String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: tomorrow)
    }

    var body: some View {
        ZStack {
            LuniferBackground()

            (luniferEnabled
                ? Color(red: 0.4, green: 0.2, blue: 0.6).opacity(0.08)
                : Color.black.opacity(0.45))
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: luniferEnabled)

            // ── Settings button ───────────────────────────
            if luniferEnabled {
                VStack {
                    HStack {
                        Spacer()
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 22, weight: .regular))
                                .foregroundColor(Color.white.opacity(0.85))
                                .padding(14)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.08))
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                        )
                                )
                                .padding(20)
                                .padding(.horizontal, 40)
                        }
                        Spacer().frame(width: 0)
                    }
                    Spacer()
                }
                .transition(.opacity)
            }

            // ── Wake-up time ──────────────────────────────
            VStack(spacing: 0) {
                if luniferEnabled {
                VStack(spacing: 12) {
                    Text("TOMORROW'S ALARM")
                        .font(.custom("DM Sans", size: 11))
                        .foregroundColor(Color.white.opacity(0.35))
                        .kerning(2.5)

                    // ── Divider above ─────────────────────────
                    Rectangle()
                        .fill(Color.white.opacity(0.95))
                        .frame(height: 1)

                    // ── Tappable alarm time row ───────────────
                    ZStack {
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(wakeUpTime)
                                .font(.custom("Libre Franklin", size: 63).weight(.light))
                                .foregroundColor(Color.white.opacity(0.95))
                                .monospacedDigit()
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            Text(wakeUpPeriod)
                                .font(.custom("Libre Franklin", size: 60).weight(.light))
                                .foregroundColor(Color.white.opacity(0.95))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        HStack {
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(Color.white.opacity(0.95))
                                .rotationEffect(.degrees(alarmExpanded ? 90 : 0))
                                .animation(.easeInOut(duration: 0.3), value: alarmExpanded)
                                .padding(.trailing, 24)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if !alarmExpanded {
                                overrideTime = calculatedAlarmDate
                                overrideActive = true
                            }
                            alarmExpanded.toggle()
                        }
                    }

                    // ── Divider below ─────────────────────────
                    Rectangle()
                        .fill(Color.white.opacity(0.95))
                        .frame(height: 1)

                    // ── Dropdown content ──────────────────────
                    if alarmExpanded {
                        VStack(spacing: 16) {
                            Text("Set custom time")
                                .font(.custom("DM Sans", size: 14))
                                .foregroundColor(Color.white.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .center)

                            DatePicker("", selection: $overrideTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .colorScheme(.dark)
                                .frame(maxWidth: .infinity)

                            Button {
                                showSound = true
                            } label: {
                                HStack {
                                    Text("Sound")
                                        .font(.custom("DM Sans", size: 14))
                                        .foregroundColor(Color.white.opacity(0.85))
                                    Spacer()
                                    Text(SoundOption.displayName(for: selectedAlarmSound))
                                        .font(.custom("DM Sans", size: 13))
                                        .foregroundColor(Color.white.opacity(0.4))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .light))
                                        .foregroundColor(Color.white.opacity(0.35))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.04))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 45)
                        .transition(.opacity.combined(with: .offset(y: -8)))
                    }

                    if !alarmExpanded {
                        Text(tomorrowDateString)
                            .font(.custom("DM Sans", size: 14))
                            .foregroundColor(Color.white.opacity(0.3))
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 32)
                .transition(.opacity)
                .onChange(of: overrideTime) { _, newTime in
                    guard overrideActive else { return }
                    Task { await LuniferAlarm.shared.scheduleAlarm(for: newTime) }
                }
                } // end if luniferEnabled
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(y: -32)

            // ── Unified toggle button — travels from bottom to center ──
            if !alarmExpanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.5)) { luniferEnabled.toggle() }
                    if luniferEnabled { Task { await LuniferAlarm.shared.cancelAlarm() } }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: luniferEnabled ? "moon.fill" : "moon.stars.fill")
                            .font(.system(size: luniferEnabled ? 13 : 15))
                            .foregroundColor(luniferEnabled
                                ? Color(red: 0.706, green: 0.588, blue: 0.902)
                                : Color.white.opacity(0.6))
                        Text(luniferEnabled ? "Turn Lunifer off" : "Turn on Lunifer")
                            .font(.custom("DM Sans", size: luniferEnabled ? 14 : 15))
                            .foregroundColor(luniferEnabled
                                ? Color.white.opacity(0.6)
                                : Color.white.opacity(0.7))
                    }
                    .padding(.horizontal, luniferEnabled ? 24 : 32)
                    .padding(.vertical, luniferEnabled ? 12 : 16)
                    .background(
                        Capsule()
                            .fill(luniferEnabled
                                ? Color(red: 0.392, green: 0.275, blue: 0.627).opacity(0.2)
                                : Color.white.opacity(0.08))
                            .overlay(Capsule().stroke(luniferEnabled
                                ? Color(red: 0.627, green: 0.471, blue: 0.863).opacity(0.3)
                                : Color.white.opacity(0.25), lineWidth: luniferEnabled ? 1 : 1.5))
                    )
                }
                .padding(.bottom, luniferEnabled ? 52 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: luniferEnabled ? .bottom : .center)
                .animation(.easeInOut(duration: 0.5), value: luniferEnabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSettings) {
            LuniferSettings(answers: $answers)
        }
        .sheet(isPresented: $showSound) {
            SoundSettingsView()
        }
    }
}

struct SoundOption {
    let displayName: String
    let filename: String

    static let all: [SoundOption] = [
        SoundOption(displayName: "Default Alarm",      filename: "DeafultAlarm.wav"),
        SoundOption(displayName: "Alarm Clock",        filename: "Alarm Clock.mp3"),
        SoundOption(displayName: "Church Bells",       filename: "Church Bells.wav"),
        SoundOption(displayName: "Crystal Bowl",       filename: "Crystal Bowl Rythym audio .m4a"),
        SoundOption(displayName: "Space",              filename: "Space.wav"),
        SoundOption(displayName: "Twin Alarm Bell",    filename: "Twin Alarm Bell.wav"),
        SoundOption(displayName: "Clock Alarm",        filename: "microsammy-clock-alarm-8761.mp3"),
    ]

    static func displayName(for filename: String) -> String {
        all.first { $0.filename == filename }?.displayName ?? filename
    }
}

struct SoundSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedAlarmSound") private var selectedAlarmSound: String = "DeafultAlarm.wav"
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.luniferBg.ignoresSafeArea()
                StarsView()

                VStack(spacing: 0) {
                    // ── Header ────────────────────────────────
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .light))
                                .foregroundColor(Color.white.opacity(0.75))
                                .frame(width: 36, height: 36)
                        }
                        Spacer()
                        Text("Sound")
                            .font(.custom("Cormorant Garamond", size: 28).weight(.light))
                            .foregroundColor(Color.white.opacity(0.9))
                        Spacer()
                        Color.clear.frame(width: 36, height: 36)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                    // ── Sound list ────────────────────────────
                    VStack(spacing: 0) {
                        ForEach(SoundOption.all, id: \.filename) { option in
                            Button {
                                selectedAlarmSound = option.filename
                                preview(option.filename)
                            } label: {
                                HStack {
                                    Text(option.displayName)
                                        .font(.custom("DM Sans", size: 15))
                                        .foregroundColor(Color.white.opacity(0.85))
                                    Spacer()
                                    if selectedAlarmSound == option.filename {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(Color(red: 0.706, green: 0.588, blue: 0.902))
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(.plain)

                            if option.filename != SoundOption.all.last?.filename {
                                Rectangle()
                                    .fill(Color.white.opacity(0.07))
                                    .frame(height: 1)
                                    .padding(.horizontal, 24)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

// ── MARK: Preview ─────────────────────────────────────────────


    private func preview(_ filename: String) {
        audioPlayer?.stop()
        guard let url = Bundle.main.url(forResource: (filename as NSString).deletingPathExtension,
                                        withExtension: (filename as NSString).pathExtension) else { return }
        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.play()
    }
}


#Preview {
    LuniferDashboard(answers: .constant({
        var a = SurveyAnswers()
        a.age       = "28"
        a.lifestyle = "commuter"
        a.calendar  = "apple"
        a.routine   = TimeValue(hours: 0, minutes: 45, auto: false)
        a.commute   = TimeValue(hours: 0, minutes: 30, auto: false)
        return a
    }()))
}
