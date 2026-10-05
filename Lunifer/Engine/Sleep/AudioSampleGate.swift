import Foundation

/// Filters audio callbacks before volume calculation or main-thread work.
nonisolated final class AudioSampleGate: @unchecked Sendable {
    private let lock = NSLock()
    private let interval: TimeInterval
    private var lastAcceptedTime: TimeInterval?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func accept(at uptime: TimeInterval) -> Bool {
        // Never block the audio callback if another callback owns the gate.
        guard lock.try() else { return false }
        defer { lock.unlock() }
        if let lastAcceptedTime, uptime - lastAcceptedTime < interval {
            return false
        }
        lastAcceptedTime = uptime
        return true
    }
}
