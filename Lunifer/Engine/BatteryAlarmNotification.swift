import Foundation
import UIKit
import UserNotifications

// ─────────────────────────────────────────────────────────────
// BatteryAlarmNotification
// ─────────────────────────────────────────────────────────────
// Predicts whether the phone will survive until the next alarm
// and notifies the user if it won't — but only within 2 hours
// of their estimated bedtime, so the warning is actionable.
//
// ── PREDICTION ALGORITHM ─────────────────────────────────────
// Rather than a single drain rate estimate, this model collects
// up to 10 real measurements and computes a mean + standard
// deviation. It then uses a CONSERVATIVE rate (mean + 1σ) for
// the prediction — meaning it intentionally over-estimates drain
// to account for nights that are heavier than average.
//
//   projected_battery = current - conservativeRate × hoursUntilAlarm
//   warn if projected_battery < 15%
//
// With < 3 samples (early days), a 25% safety buffer is applied
// to the default rate until enough real data is collected.
//
// ── NOTIFICATION WINDOW ──────────────────────────────────────
// Estimated bedtime = alarmTime − user's expected sleep duration
// Notification window opens 2 hours before estimated bedtime.
// Nothing is sent before that window — the warning is only
// useful if the user still has time to plug in before sleeping.
//
//   Example: alarm at 7:00 AM, sleeps 8h → bedtime ≈ 11:00 PM
//   Notification window: 9:00 PM → 7:00 AM
//
// ── SMART SUPPRESSION ────────────────────────────────────────
// - Silent while charging (no risk)
// - Warns once per alarm (no re-spam as battery drips down)
// - Warning cancelled if user plugs in

@MainActor
final class BatteryAlarmNotification {

    static let shared = BatteryAlarmNotification()

    // ── Thresholds ────────────────────────────────────────────

    /// Predicted battery at alarm time below this triggers a warning.
    /// Set to 0 so the notification only fires if the phone is predicted to die.
    private let warningThreshold: Float  = 0.0

    /// Default standby drain rate used before real data is collected.
    /// 5%/hr is a conservative estimate for modern iPhones in standby.
    private let defaultDrainRatePerHour: Double = 0.05

    /// Safety multiplier applied when fewer than 3 samples exist.
    private let lowDataSafetyBuffer: Double = 1.25

    /// Maximum drain samples to retain. Older ones are dropped.
    private let maxSamples = 10

    // ── UserDefaults keys ─────────────────────────────────────

    private let drainSamplesKey     = "lunifer_battery_drain_samples"
    private let lastCheckTimeKey    = "lunifer_battery_last_check_time"
    private let lastCheckLevelKey   = "lunifer_battery_last_check_level"
    private let lastWarnedAlarmKey  = "lunifer_battery_last_warned_alarm"

    private let notificationID = "lunifer.battery.warning"

    // ── Lifecycle ─────────────────────────────────────────────

    func startMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBatteryStateChange),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBatteryLevelChange),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )

        Task { await checkAndWarnIfNeeded() }
    }

    @objc private func handleBatteryStateChange() {
        recordDrainSample()
        Task { await checkAndWarnIfNeeded() }
    }

    @objc private func handleBatteryLevelChange() {
        recordDrainSample()
        Task { await checkAndWarnIfNeeded() }
    }

    // ── Core check ────────────────────────────────────────────

    func checkAndWarnIfNeeded() async {
        // Respect the user's notification preference
        guard UserDefaults.standard.object(forKey: "batteryAlertEnabled") as? Bool != false else { return }

        let device = UIDevice.current
        guard device.batteryLevel >= 0 else { return }

        // Charging — no risk, cancel any existing warning
        if device.batteryState == .charging || device.batteryState == .full {
            cancelWarning()
            return
        }

        guard let alarmTime = LuniferAlarm.shared.scheduledWakeTime else {
            cancelWarning()
            return
        }

        let now             = Date()
        let hoursUntilAlarm = alarmTime.timeIntervalSince(now) / 3600.0

        guard hoursUntilAlarm > 0 && hoursUntilAlarm <= 24 else {
            cancelWarning()
            return
        }

        // ── Notification window check ─────────────────────────
        // Only notify within 2 hours of the user's estimated bedtime.
        // Sending earlier is premature — the situation may change.
        let estimatedBedtime      = bedtimeEstimate(before: alarmTime)
        let notificationWindowOpen = estimatedBedtime.addingTimeInterval(-2 * 3600)

        guard now >= notificationWindowOpen else {
            // Too early in the day — check again later but don't notify yet
            return
        }

        // ── Drain prediction ──────────────────────────────────
        let currentLevel    = device.batteryLevel
        let conservativeRate = conservativeDrainRate()
        let projectedLevel  = currentLevel - Float(conservativeRate * hoursUntilAlarm)

        print("🔋 Battery check: \(Int(currentLevel * 100))% now, " +
              "projected \(Int(projectedLevel * 100))% at alarm " +
              "(rate: \(String(format: "%.1f", conservativeRate * 100))%/hr)")

        if projectedLevel < warningThreshold {
            // Warn once per alarm — don't re-notify for the same alarm time
            let lastWarnedTS  = UserDefaults.standard.double(forKey: lastWarnedAlarmKey)
            let alreadyWarned = abs(lastWarnedTS - alarmTime.timeIntervalSince1970) < 60

            guard !alreadyWarned else { return }

            await sendWarning(
                currentLevel: currentLevel,
                projectedLevel: projectedLevel,
                alarmTime: alarmTime
            )
            UserDefaults.standard.set(alarmTime.timeIntervalSince1970, forKey: lastWarnedAlarmKey)
        } else {
            cancelWarning()
        }
    }

    // ── Bedtime estimation ────────────────────────────────────
    // Derives the user's expected bedtime by subtracting their
    // recommended (or historically measured) sleep duration from
    // the alarm time.

    private func bedtimeEstimate(before alarmTime: Date) -> Date {
        let sleepHours = expectedSleepDuration()
        return alarmTime.addingTimeInterval(-sleepHours * 3600)
    }

    private func expectedSleepDuration() -> Double {
        // Use real measured average if we have enough nights
        if let avg = SleepHistoryManager.shared.averageDuration(days: 7) {
            return avg
        }
        // Fall back to age-based recommendation from survey
        if let answers = SurveyAnswers.loadFromDefaults() {
            return SleepDurationModel.baselineForAge(answers.age)
        }
        // Last resort: 8 hours
        return 8.0
    }

    // ── Conservative drain rate ───────────────────────────────
    // Uses the statistical spread of historical measurements to
    // produce a rate that's intentionally pessimistic — we'd
    // rather warn unnecessarily than fail to warn when needed.

    private func conservativeDrainRate() -> Double {
        let samples = loadDrainSamples()

        guard samples.count >= 3 else {
            // Not enough data yet — use default with safety buffer
            return defaultDrainRatePerHour * lowDataSafetyBuffer
        }

        let mean = samples.reduce(0, +) / Double(samples.count)

        // Standard deviation
        let variance = samples.reduce(0) { $0 + pow($1 - mean, 2) } / Double(samples.count)
        let std      = sqrt(variance)

        // Conservative estimate: mean + 1 standard deviation
        // This means ~84% of nights will drain less than our prediction
        let conservative = mean + std

        // Never go below the default (catches unrealistically low measurements)
        return max(conservative, defaultDrainRatePerHour)
    }

    // ── Drain sample recording ────────────────────────────────
    // Records a drain rate measurement each time battery level
    // drops while unplugged. Keeps the most recent `maxSamples`.

    private func recordDrainSample() {
        let device = UIDevice.current

        guard device.batteryState == .unplugged,
              device.batteryLevel >= 0 else {
            // Update baseline even if we can't measure yet
            storeCheckpoint(device.batteryLevel)
            return
        }

        let now           = Date().timeIntervalSince1970
        let lastCheckTime = UserDefaults.standard.double(forKey: lastCheckTimeKey)
        let lastLevel     = UserDefaults.standard.float(forKey: lastCheckLevelKey)

        if lastCheckTime > 0 && lastLevel > 0 {
            let hoursElapsed = (now - lastCheckTime) / 3600.0
            let levelDrop    = Double(lastLevel - device.batteryLevel)

            // Require at least 30 min elapsed and 1% drop for a valid sample
            if hoursElapsed >= 0.5 && levelDrop > 0.01 {
                let rate = levelDrop / hoursElapsed

                // Only accept physically plausible rates (0.5% – 25% per hour)
                if rate >= 0.005 && rate <= 0.25 {
                    var samples = loadDrainSamples()
                    samples.append(rate)

                    // Keep only the most recent samples
                    if samples.count > maxSamples {
                        samples = Array(samples.suffix(maxSamples))
                    }

                    saveDrainSamples(samples)
                    print("🔋 Drain sample recorded: \(String(format: "%.1f", rate * 100))%/hr " +
                          "(\(samples.count) total samples)")
                }
            }
        }

        storeCheckpoint(device.batteryLevel)
    }

    private func storeCheckpoint(_ level: Float) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckTimeKey)
        UserDefaults.standard.set(level, forKey: lastCheckLevelKey)
    }

    // ── Drain sample persistence ──────────────────────────────

    private func loadDrainSamples() -> [Double] {
        UserDefaults.standard.array(forKey: drainSamplesKey) as? [Double] ?? []
    }

    private func saveDrainSamples(_ samples: [Double]) {
        UserDefaults.standard.set(samples, forKey: drainSamplesKey)
    }

    // ── Notification ──────────────────────────────────────────

    private func sendWarning(
        currentLevel: Float,
        projectedLevel: Float,
        alarmTime: Date
    ) async {
        let center   = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        let content   = UNMutableNotificationContent()
        content.title = "Charge your phone tonight"

        let alarmString = alarmTime.formatted(date: .omitted, time: .shortened)
        let batteryPct  = Int(currentLevel * 100)

        content.body = "Your phone is at \(batteryPct)% and is predicted to die before your \(alarmString) alarm. Plug in before you sleep."

        content.sound             = .default
        content.interruptionLevel = .timeSensitive

        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])

        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            print("🔋 Battery warning sent — \(batteryPct)% now, projected \(Int(projectedLevel * 100))% at \(alarmString)")
        } catch {
            print("❌ Battery warning failed: \(error.localizedDescription)")
        }
    }

    private func cancelWarning() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
    }
}
