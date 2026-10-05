import Foundation

/// Invalidates work that was started before sign-out, including suspended tasks.
@MainActor
final class BackgroundActivitySession {
    static let shared = BackgroundActivitySession(persistSignOut: true)
    private(set) var generation = UUID()
    private(set) var isStopped: Bool
    private let persistSignOut: Bool
    private static let stoppedKey = "lunifer_background_stopped_after_signout"

    init(persistSignOut: Bool = false) {
        self.persistSignOut = persistSignOut
        isStopped = persistSignOut && UserDefaults.standard.bool(forKey: Self.stoppedKey)
    }

    func stop() {
        isStopped = true
        if persistSignOut { UserDefaults.standard.set(true, forKey: Self.stoppedKey) }
        generation = UUID()
    }

    func resume() {
        guard isStopped else { return }
        generation = UUID()
        isStopped = false
        if persistSignOut { UserDefaults.standard.removeObject(forKey: Self.stoppedKey) }
    }

    func accepts(_ generation: UUID) -> Bool {
        !isStopped && self.generation == generation
    }
}
