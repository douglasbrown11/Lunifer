import Foundation
import Combine
import HealthKit

// ─────────────────────────────────────────────────────────────
// HealthKitManager
// ─────────────────────────────────────────────────────────────
// Reads Apple Watch sleep from HealthKit and feeds it into the
// existing sleep history pipeline as authoritative (wearable-priority)
// nights. You don't talk to the watch directly — the watch writes
// sleep into HealthKit on the paired iPhone, and this reads it.
//
// SCOPE (intentional):
//   • This is a *data source*, not a recommendation source. The
//     target "recommended hours" still comes from the existing engine
//     (`SleepDurationModel.baselineForAge` / manual), so HealthKit
//     does NOT plug into `WearableRecommendationStore`. It only makes
//     the *measured* nights accurate.
//   • Nights are recorded with `source: .wearable`, so they take
//     per-night precedence over the CoreMotion estimate. The CoreMotion
//     `SleepTracker` keeps running every night as a backup; on nights
//     the watch has no data (dead / not worn / removed), the on-device
//     estimate stands instead.
//
// NOTE: Apple Watch sleep is RETROSPECTIVE — it's written to HealthKit
// after the user wakes, so this improves completed-night accuracy and
// the next day's planning, not live "asleep right now" detection.
//
// Setup required (outside this file):
//   • HealthKit capability enabled on the App ID / in Xcode (writes the
//     `com.apple.developer.healthkit` entitlement).
//   • `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription`
//     in Info.plist. App Store validation requires both purpose strings for
//     HealthKit-enabled apps, even though Lunifer requests read-only access.

@MainActor
final class HealthKitManager: ObservableObject {

    static let shared = HealthKitManager()

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastSyncDate: Date? = nil
    @Published private(set) var errorMessage: String? = nil

    private let healthStore = HKHealthStore()

    /// Reentrancy guard so overlapping refresh calls (e.g. the dashboard and
    /// Sleep Insights both triggering a refresh in one session) don't run two
    /// imports at once. Safe because the class is @MainActor.
    private var isImporting = false

    private enum Keys {
        static let connected = "healthKitConnected"
        static let lastSync  = "healthKitLastSyncDate"
    }

    private init() {
        isConnected  = UserDefaults.standard.bool(forKey: Keys.connected)
        lastSyncDate = UserDefaults.standard.object(forKey: Keys.lastSync) as? Date
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var sleepType: HKCategoryType {
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    }

    /// HealthKit deliberately hides read-authorization status, so we can't ask
    /// "did the user grant read access?". Instead we remember that the user opted
    /// in (this flag) and verify by attempting a read.
    private var connectedFlag: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.connected) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.connected) }
    }

    // MARK: - Connect / disconnect

    /// Requests HealthKit read access to sleep data and imports recent nights.
    func connect() async {
        guard isAvailable else {
            errorMessage = "Health data isn't available on this device."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: [sleepType])
            connectedFlag = true
            isConnected = true
            await importRecentSleep()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stops reading from HealthKit. We can't revoke the system permission from
    /// the app — the user does that in Settings — so this just turns Lunifer's
    /// use of it off. Already-recorded wearable nights are left in place.
    func disconnect() {
        connectedFlag = false
        UserDefaults.standard.removeObject(forKey: Keys.lastSync)
        isConnected = false
        lastSyncDate = nil
        errorMessage = nil
    }

    /// Re-reads HealthKit on every call — no staleness gate. Unlike the
    /// network-bound WHOOP/Oura refreshers, HealthKit reads are local and cheap,
    /// so refreshing on every dashboard / Sleep Insights open lets "last night"
    /// appear as soon as the user opens the app in the morning. The reentrancy
    /// guard in importRecentSleep() prevents overlapping reads in one session.
    func refreshIfNeeded() {
        guard isConnected, isAvailable else { return }
        Task { await importRecentSleep() }
    }

    // MARK: - Import

    /// Reads the last 7 days of sleep from HealthKit (Apple Watch source),
    /// groups samples into nights, and records each as a wearable-priority entry.
    func importRecentSleep() async {
        guard isAvailable, !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -7, to: end) else { return }

        let samples = await fetchAsleepSamples(from: start, to: end)
        guard !samples.isEmpty else { return }

        for night in Self.groupIntoNights(samples) {
            // Only record realistic nights, consistent with the rest of the app.
            guard night.durationHours >= 3.0, night.durationHours <= 12.0 else { continue }
            SleepHistoryManager.shared.recordNight(
                date: night.wake,
                duration: night.durationHours,
                onset: night.onset,
                wake: night.wake,
                source: .wearable
            )
        }

        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: Keys.lastSync)
    }

    private func fetchAsleepSamples(from start: Date, to end: Date) async -> [HKCategorySample] {
        // Capture on the MainActor before entering the nonisolated HealthKit callback,
        // avoiding the "MainActor-isolated property referenced from nonisolated context" warning.
        let values = Self.asleepValues
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let asleep = (samples as? [HKCategorySample] ?? [])
                    .filter { values.contains($0.value) }
                continuation.resume(returning: asleep)
            }
            healthStore.execute(query)
        }
    }

    /// The "asleep" category values (any sleep stage). `inBed` and `awake` excluded.
    private static let asleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue
    ]

    private struct Night {
        let onset: Date
        let wake: Date
        let durationHours: Double
    }

    /// Groups time-sorted asleep samples into nights, splitting on gaps > 2 hours.
    /// Duration is the sum of asleep intervals (so brief awakenings within a night
    /// don't inflate it); onset is the first asleep start, wake the last asleep end.
    private static func groupIntoNights(_ samples: [HKCategorySample]) -> [Night] {
        guard !samples.isEmpty else { return [] }
        let sorted = samples.sorted { $0.startDate < $1.startDate }
        let gapThreshold: TimeInterval = 2 * 60 * 60

        var nights: [Night] = []
        var sessionStart = sorted[0].startDate
        var sessionEnd   = sorted[0].endDate
        var asleepSeconds = sorted[0].endDate.timeIntervalSince(sorted[0].startDate)

        for sample in sorted.dropFirst() {
            if sample.startDate.timeIntervalSince(sessionEnd) > gapThreshold {
                nights.append(Night(onset: sessionStart, wake: sessionEnd,
                                    durationHours: asleepSeconds / 3600.0))
                sessionStart = sample.startDate
                sessionEnd   = sample.endDate
                asleepSeconds = sample.endDate.timeIntervalSince(sample.startDate)
            } else {
                sessionEnd = max(sessionEnd, sample.endDate)
                asleepSeconds += sample.endDate.timeIntervalSince(sample.startDate)
            }
        }
        nights.append(Night(onset: sessionStart, wake: sessionEnd,
                            durationHours: asleepSeconds / 3600.0))
        return nights
    }

    // MARK: - Cleanup

    func clearLocalData() {
        Self.clearStoredData()
        isConnected = false
        lastSyncDate = nil
    }

    /// Nonisolated wipe of persisted keys, callable from non-MainActor cleanup
    /// (`AccountDataManager`). Mirrors the keys above.
    nonisolated static func clearStoredData() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "healthKitConnected")
        defaults.removeObject(forKey: "healthKitLastSyncDate")
    }
}
