import SwiftUI
import Combine
import AVFoundation

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

    // The selected alarm sound filename, set from the sound picker in the dashboard.
    @AppStorage("selectedAlarmSound") private var selectedAlarmSound: String = "DeafultAlarm.wav"

    @State private var currentTime = Date()
    @State private var audioPlayer: AVAudioPlayer? = nil
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
        .onAppear   { startPlayingSound() }
        .onDisappear { stopPlayingSound() }
        .onReceive(ticker) { _ in currentTime = Date() }
    }

    // ── Sound playback ───────────────────────────────────────

    /// Starts playing the user's selected alarm sound on a loop.
    /// Configures the audio session for .playback so the sound is
    /// audible even when the ringer switch is off (same category
    /// used by music and video apps). .duckOthers lowers competing
    /// audio (e.g. any system alarm tone AlarmKit may produce) so
    /// Lunifer's custom sound is clearly heard.
    private func startPlayingSound() {
        let filename = selectedAlarmSound
        let name = (filename as NSString).deletingPathExtension
        let ext  = (filename as NSString).pathExtension.isEmpty ? "wav" : (filename as NSString).pathExtension

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("⚠️ Alarm sound '\(filename)' not found in bundle — no custom sound will play.")
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1  // Loop until the user stops or snoozes
            player.volume = 1.0
            player.prepareToPlay()
            player.play()
            audioPlayer = player

            print("🔊 Playing alarm sound: \(filename)")
        } catch {
            print("❌ Failed to play alarm sound '\(filename)': \(error.localizedDescription)")
        }
    }

    /// Stops and releases the audio player, then deactivates the
    /// audio session so other apps can resume their audio normally.
    private func stopPlayingSound() {
        audioPlayer?.stop()
        audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        print("🔇 Alarm sound stopped")
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
