import Foundation

/// A running population-variance calculator fed one raw sample at a time. Both `MotionMonitor`
/// (accelerometer magnitude) and `MicMonitor` (microphone amplitude) flush one of these every
/// minute to produce the per-minute variance values `SleepEngine` reasons about.
struct VarianceAggregator {
    private var samples: [Double] = []

    mutating func add(_ value: Double) {
        samples.append(value)
    }

    /// Population variance of everything added since the last `reset()`. `nil` until there are
    /// at least two samples (variance is undefined for 0 or 1 points).
    var variance: Double? {
        guard samples.count >= 2 else { return nil }
        let mean = samples.reduce(0, +) / Double(samples.count)
        let sumSquaredDiffs = samples.reduce(0.0) { partial, x in partial + (x - mean) * (x - mean) }
        return sumSquaredDiffs / Double(samples.count)
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }
}

/// The real, testable sleep-onset heuristic described in the SPEC: no ML model, just a
/// sustained drop in per-minute motion/mic variance. Deliberately simple so it's verifiable
/// against hand-computed values, not a black box.
enum SleepEngine {
    /// A per-minute combined variance at or below this is considered "still".
    static let varianceThreshold: Double = 0.02
    /// How many consecutive still minutes confirm sleep onset.
    static let sustainedMinutes: Int = 8

    /// Combines a minute's motion variance and mic variance into one number for the detector.
    /// Either signal alone being active (moving OR making noise) should count as "not still".
    static func combinedVariance(motion: Double, mic: Double) -> Double {
        max(motion, mic)
    }

    /// Scans per-minute variance samples for the first run of `sustainedMinutes` consecutive
    /// values at or under `threshold`, and returns the index where that run *began* — onset is
    /// back-dated to when stillness started, not to the minute it was confirmed, matching how
    /// real actigraphy-based sleep-onset detection works. Returns `nil` if no such run exists.
    static func detectOnsetIndex(
        variances: [Double],
        threshold: Double = varianceThreshold,
        sustainedMinutes: Int = sustainedMinutes
    ) -> Int? {
        guard sustainedMinutes > 0 else { return nil }
        var runStart: Int?
        var runLength = 0
        for (i, v) in variances.enumerated() {
            if v <= threshold {
                if runStart == nil { runStart = i }
                runLength += 1
                if runLength >= sustainedMinutes {
                    return runStart
                }
            } else {
                runStart = nil
                runLength = 0
            }
        }
        return nil
    }

    /// The precise wake instant: onset plus the anchor's total duration.
    static func wakeDate(from onset: Date, mode: AnchorDurationMode) -> Date {
        onset.addingTimeInterval(mode.totalHours * 3600)
    }
}

/// The quirky feature: distinguishes "still asleep but lightly" from "deep sleep, don't touch
/// it" using the same variance signal, so the second-chance snooze is honest rather than always
/// offered.
enum SnoozeEvaluator {
    /// Variance at or below this, sustained, reads as a near-total-stillness deep-sleep
    /// signature rather than the low-but-nonzero shifting of light sleep.
    static let deepSleepCeiling: Double = 0.004
    /// Minutes of sustained near-zero variance required to call it deep sleep.
    static let sustainedMinutesForLockout: Int = 6
    static let lockoutReason = "Your motion signature still looks like deep sleep — waking you again right now would be rough, so second-chance snooze is off the table tonight."

    static func evaluate(snoozeWindowVariances: [Double]) -> SnoozeDecision {
        guard !snoozeWindowVariances.isEmpty else {
            // No samples yet (e.g. the app was fully backgrounded through the snooze window) —
            // default to giving the user the benefit of the doubt rather than locking them out
            // on missing data.
            return .allowed
        }
        var longestDeepRun = 0
        var currentRun = 0
        for v in snoozeWindowVariances {
            if v <= deepSleepCeiling {
                currentRun += 1
                longestDeepRun = max(longestDeepRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        if longestDeepRun >= sustainedMinutesForLockout {
            return .lockedOut(reason: lockoutReason)
        }
        return .allowed
    }
}
