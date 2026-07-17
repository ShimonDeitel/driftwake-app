import AVFoundation
import Foundation

/// Wraps `AVAudioRecorder` metering (never actual audio content) to produce one per-minute
/// mic-amplitude variance value — the secondary signal that confirms motion-based stillness
/// with room-noise stillness too. No audio is ever written to a persistent file or transmitted;
/// only the metered decibel level is read, in real time, then discarded.
@MainActor
final class MicMonitor: NSObject, ObservableObject {
    @Published private(set) var latestVariance: Double = 0
    @Published private(set) var isRunning = false

    private var recorder: AVAudioRecorder?
    private var sampleTimer: Timer?
    private var minuteTimer: Timer?
    private var aggregator = VarianceAggregator()

    func start() {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("driftwake-meter.caf")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatAppleLossless),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
        ]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return }
        r.isMeteringEnabled = true
        r.record()
        recorder = r
        aggregator.reset()

        sampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.flushMinute()
        }
        isRunning = true
    }

    func stop() {
        sampleTimer?.invalidate()
        sampleTimer = nil
        minuteTimer?.invalidate()
        minuteTimer = nil
        recorder?.stop()
        recorder = nil
        aggregator.reset()
        isRunning = false
    }

    private func sample() {
        guard let recorder else { return }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0) // roughly -160 (silent) ... 0 (max)
        aggregator.add(Self.linearAmplitude(fromDecibels: db))
    }

    private func flushMinute() {
        latestVariance = aggregator.variance ?? latestVariance
        aggregator.reset()
    }

    /// Maps AVAudioRecorder's dBFS metering value onto a 0...1 linear amplitude so it's on a
    /// comparable scale to motion-variance units. A -60dB floor is treated as effective
    /// silence for a bedroom (anything quieter reads the same as dead silence).
    nonisolated static func linearAmplitude(fromDecibels db: Float) -> Double {
        guard db.isFinite else { return 0 }
        let clamped = max(-60, min(0, db))
        return Double(pow(10, clamped / 20))
    }

    deinit {
        sampleTimer?.invalidate()
        minuteTimer?.invalidate()
    }
}
