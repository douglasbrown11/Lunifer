import Foundation
import AVFoundation
import Combine

//continuously converts microphone sound into a privacy-safe "how active is this room" score and a "how long has it been quiet" timer, so the sleep engine won't mistake a noisy, still-awake room for sleep.


@MainActor
final class AmbientAudioMonitor: ObservableObject {

    @Published private(set) var roomActivityScore: Double = 0
    @Published private(set) var quietDurationMinutes: Double = .infinity

    private struct Sample {
        let date: Date
        let decibels: Double
    }

    private let engine = AVAudioEngine()
    private var samples: [Sample] = []
    private var lastActiveNoiseDate: Date? = nil

    private let rollingWindow: TimeInterval = 10 * 60
    private let sampleInterval: TimeInterval = 5
    private let minimumSamplesForDecision = 6
    private var lastAcceptedSampleDate: Date = .distantPast

    func start() {
        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            roomActivityScore = 0
            quietDurationMinutes = .infinity
            return
        }
        guard !engine.isRunning else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true, options: [])

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                let decibels = Self.decibels(from: buffer)
                Task { @MainActor [weak self] in
                    self?.record(decibels: decibels)
                }
            }

            engine.prepare()
            try engine.start()
        } catch {
            print("⚠️ AmbientAudioMonitor failed to start: \(error.localizedDescription)")
            stop()
        }
    }

    func stop() {
        if engine.inputNode.numberOfInputs > 0 {
            engine.inputNode.removeTap(onBus: 0)
        }
        engine.stop()
    }

    private func record(decibels: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastAcceptedSampleDate) >= sampleInterval else { return }
        lastAcceptedSampleDate = now

        samples.append(Sample(date: now, decibels: decibels))
        samples.removeAll { now.timeIntervalSince($0.date) > rollingWindow }

        recalculateActivity(now: now)
    }

    private func recalculateActivity(now: Date) {
        guard samples.count >= minimumSamplesForDecision else {
            roomActivityScore = 0
            quietDurationMinutes = .infinity
            return
        }

        let values = samples.map(\.decibels)
        let baseline = percentile(values, p: 0.20)
        let average = values.reduce(0, +) / Double(values.count)
        let variance = values
            .map { pow($0 - average, 2) }
            .reduce(0, +) / Double(values.count)
        let standardDeviation = sqrt(variance)

        let burstThreshold = baseline + 10
        let loudBurstRatio = Double(values.filter { $0 >= burstThreshold }.count) / Double(values.count)
        let variationScore = min(max((standardDeviation - 3) / 9, 0), 1)
        let burstScore = min(loudBurstRatio / 0.35, 1)

        roomActivityScore = max(variationScore, burstScore)

        if roomActivityScore > 0.55 {
            lastActiveNoiseDate = now
            quietDurationMinutes = 0
        } else if let lastActiveNoiseDate {
            quietDurationMinutes = now.timeIntervalSince(lastActiveNoiseDate) / 60
        } else {
            quietDurationMinutes = .infinity
        }
    }

    private static func decibels(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData,
              buffer.frameLength > 0 else {
            return -120
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        var sumSquares: Float = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                let sample = samples[frame]
                sumSquares += sample * sample
            }
        }

        let meanSquare = sumSquares / Float(frameLength * max(channelCount, 1))
        let rms = sqrt(meanSquare)
        guard rms > 0 else { return -120 }
        return max(20 * log10(Double(rms)), -120)
    }

    private func percentile(_ values: [Double], p: Double) -> Double {
        guard !values.isEmpty else { return -120 }
        let sorted = values.sorted()
        let index = min(max(Int(Double(sorted.count - 1) * p), 0), sorted.count - 1)
        return sorted[index]
    }
}
