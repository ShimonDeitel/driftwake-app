import XCTest
@testable import Driftwake

final class DriftwakeLogicTests: XCTestCase {

    // MARK: SleepEngine — onset detection

    func testDetectOnsetIndex_FindsSustainedStillRun() {
        // 3 restless minutes, then 8 still minutes starting at index 3.
        let variances: [Double] = [0.5, 0.4, 0.3, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01]
        let onset = SleepEngine.detectOnsetIndex(variances: variances)
        XCTAssertEqual(onset, 3)
    }

    func testDetectOnsetIndex_NeverSustainedReturnsNil() {
        // Two runs of exactly 7 still minutes, each broken by one restless minute — never
        // reaches the required 8 in a row.
        let variances: [Double] = Array(repeating: 0.01, count: 7) + [0.5] + Array(repeating: 0.01, count: 7)
        XCTAssertNil(SleepEngine.detectOnsetIndex(variances: variances))
    }

    // MARK: SleepEngine — wake time math

    func testWakeDate_HoursMode() {
        let onset = Date(timeIntervalSince1970: 0)
        let wake = SleepEngine.wakeDate(from: onset, mode: .hours(5.5))
        XCTAssertEqual(wake.timeIntervalSince1970, 5.5 * 3600, accuracy: 0.001)
    }

    func testWakeDate_CyclesModeIsNinetyMinuteMultiples() {
        let onset = Date(timeIntervalSince1970: 0)
        let wake = SleepEngine.wakeDate(from: onset, mode: .cycles(4))
        // 4 cycles * 90 minutes = 360 minutes = 21,600 seconds.
        XCTAssertEqual(wake.timeIntervalSince1970, 21_600, accuracy: 0.001)
    }

    // MARK: SnoozeEvaluator — the quirky feature

    func testSnoozeEvaluator_LocksOutOnSustainedDeepSleep() {
        let variances: [Double] = [0.01, 0.002, 0.001, 0.003, 0.002, 0.001, 0.0005, 0.01]
        let decision = SnoozeEvaluator.evaluate(snoozeWindowVariances: variances)
        guard case .lockedOut = decision else {
            return XCTFail("expected a lockout for 6 consecutive near-zero-variance minutes")
        }
    }

    func testSnoozeEvaluator_AllowsWhenDeepRunIsTooShort() {
        // Longest near-zero run is 5, one short of the 6-minute lockout threshold.
        let variances: [Double] = [0.002, 0.001, 0.003, 0.002, 0.001, 0.01, 0.002, 0.001, 0.003, 0.002, 0.001]
        XCTAssertEqual(SnoozeEvaluator.evaluate(snoozeWindowVariances: variances), .allowed)
    }

    func testSnoozeEvaluator_AllowsWhenNoDataYet() {
        XCTAssertEqual(SnoozeEvaluator.evaluate(snoozeWindowVariances: []), .allowed)
    }

    // MARK: VarianceAggregator

    func testVarianceAggregator_ComputesPopulationVariance() {
        var aggregator = VarianceAggregator()
        for sample in [1.0, 2.0, 3.0, 4.0, 5.0] { aggregator.add(sample) }
        // mean = 3, squared diffs = 4,1,0,1,4 -> sum 10 -> variance = 10/5 = 2.0
        XCTAssertEqual(aggregator.variance!, 2.0, accuracy: 0.0001)
    }

    func testVarianceAggregator_NilBeforeTwoSamples() {
        var aggregator = VarianceAggregator()
        XCTAssertNil(aggregator.variance)
        aggregator.add(1.0)
        XCTAssertNil(aggregator.variance)
        aggregator.add(2.0)
        XCTAssertNotNil(aggregator.variance)
    }

    // MARK: AnchorDurationMode clamping

    func testAnchorDurationMode_ClampsToSupportedRange() {
        XCTAssertEqual(AnchorDurationMode.clampedHours(15).totalHours, AnchorDurationMode.maxHours, accuracy: 0.001)
        XCTAssertEqual(AnchorDurationMode.clampedHours(1).totalHours, AnchorDurationMode.minHours, accuracy: 0.001)
        guard case .cycles(let low) = AnchorDurationMode.clampedCycles(1) else { return XCTFail("expected .cycles") }
        XCTAssertEqual(low, AnchorDurationMode.minCycles)
        guard case .cycles(let high) = AnchorDurationMode.clampedCycles(10) else { return XCTFail("expected .cycles") }
        XCTAssertEqual(high, AnchorDurationMode.maxCycles)
    }

    // MARK: GrogginessLog — 14-day window

    func testGrogginessLog_LastDaysKeepsInclusiveFourteenDayBoundary() {
        let reference = Date(timeIntervalSince1970: 100_000_000)
        let dayOffsetsAndMarkers: [(Double, Double)] = [
            (0, 6.0), (-5, 6.5), (-13, 7.0), (-14, 7.5), (-20, 8.0)
        ]
        let entries = dayOffsetsAndMarkers.map { offset, marker in
            GrogginessEntry(
                date: reference.addingTimeInterval(offset * 86_400),
                anchorDurationHours: marker,
                rating: 3
            )
        }
        let kept = GrogginessLog.lastDays(entries, days: 14, referenceDate: reference)
        // -20 days falls outside the 14-day window; the other four (including the exact
        // 14-day boundary) are kept, sorted oldest-first.
        XCTAssertEqual(kept.count, 4)
        XCTAssertEqual(kept.first?.anchorDurationHours ?? -1, 7.5, accuracy: 0.001)
        XCTAssertEqual(kept.last?.anchorDurationHours ?? -1, 6.0, accuracy: 0.001)
    }

    // MARK: MicMonitor — decibel-to-linear-amplitude mapping

    func testMicMonitor_LinearAmplitudeMapping() {
        XCTAssertEqual(MicMonitor.linearAmplitude(fromDecibels: 0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(MicMonitor.linearAmplitude(fromDecibels: -20), 0.1, accuracy: 0.0001)
        XCTAssertEqual(MicMonitor.linearAmplitude(fromDecibels: -60), 0.001, accuracy: 0.0001)
        // Anything quieter than -60dB floors at the same value as -60dB.
        XCTAssertEqual(MicMonitor.linearAmplitude(fromDecibels: -120), 0.001, accuracy: 0.0001)
    }
}
