import SwiftUI
import Combine

// ─────────────────────────────────────────────────────────────
// LuniferAlarmScreen.swift
// Shown as a full-screen overlay whenever the alarm is firing.
// Displays the current time and two actions: Snooze and Stop.
// ─────────────────────────────────────────────────────────────

struct LuniferAlarmScreen: View {

    @StateObject private var alarm = LuniferAlarm.shared

    // Snooze duration is stored in UserDefaults so it persists across launches.
    // Adjusted in LuniferSettings.
    // Note: swap "System" for "Roboto" here once Roboto is added to the Xcode project.
    @AppStorage("snoozeMinutes") private var snoozeMinutes: Int = 5

    @State private var currentTime = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                Spacer()

                // ── Time display ─────────────────────────────
                Text(timeString)
                    .font(.system(size: 88, weight: .thin))
                    // monospacedDigit prevents the digits from shifting width
                    // as the seconds tick — keeps the layout stable
                    .monospacedDigit()
                    .foregroundColor(.white)

                Text(amPmString)
                    .font(.system(size: 22, weight: .thin))
                    .foregroundColor(Color.white.opacity(0.5))
                    .padding(.top, 8)

                Spacer()

                // ── Buttons ──────────────────────────────────
                VStack(spacing: 16) {

                    // Snooze
                    Button {
                        Task { await alarm.snooze(minutes: snoozeMinutes) }
                    } label: {
                        Text("Snooze · \(snoozeMinutes) min")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                                    )
                            )
                    }

                    // Stop
                    Button {
                        Task { await alarm.stopAlarm() }
                    } label: {
                        Text("Stop")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white)
                            )
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
        .onReceive(ticker) { _ in currentTime = Date() }
    }

    // ── Time formatting ──────────────────────────────────────

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f.string(from: currentTime)
    }

    private var amPmString: String {
        let f = DateFormatter()
        f.dateFormat = "a"
        return f.string(from: currentTime).uppercased()
    }
}

#Preview {
    LuniferAlarmScreen()
}
