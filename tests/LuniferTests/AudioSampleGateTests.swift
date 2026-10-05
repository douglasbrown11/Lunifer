import XCTest
@testable import Lunifer

final class AudioSampleGateTests: XCTestCase {
    func testFiveSecondBoundary() {
        let gate = AudioSampleGate(interval: 5)
        XCTAssertTrue(gate.accept(at: 100))
        XCTAssertFalse(gate.accept(at: 104.999))
        XCTAssertTrue(gate.accept(at: 105))
        XCTAssertFalse(gate.accept(at: 105))
        XCTAssertTrue(gate.accept(at: 110))
    }

    func testTypicalAudioStreamKeepsSameSamplesWithoutProcessingRejectedBuffers() {
        let gate = AudioSampleGate(interval: 5)
        var previousAccepted: Double?
        var previousSamples: [Int] = []
        var earlySamples: [Int] = []
        // Ten minutes of 4096-frame callbacks at 48 kHz.
        for index in 0..<7032 {
            let time = Double(index) * 4096 / 48_000
            if previousAccepted == nil || time - previousAccepted! >= 5 {
                previousAccepted = time
                previousSamples.append(index)
            }
            if gate.accept(at: time) {
                earlySamples.append(index)
            }
        }
        XCTAssertEqual(earlySamples, previousSamples)
        XCTAssertEqual(earlySamples.count, 120)
    }

    func testRestartAcceptsFirstSampleAndLongGapDoesNotCatchUp() {
        let gate = AudioSampleGate(interval: 5)
        XCTAssertTrue(gate.accept(at: 100))
        XCTAssertTrue(gate.accept(at: 1000))
        XCTAssertFalse(gate.accept(at: 1000.1))
        XCTAssertTrue(AudioSampleGate(interval: 5).accept(at: 1000.1))
    }
}
