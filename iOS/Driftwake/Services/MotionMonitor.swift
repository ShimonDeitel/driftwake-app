import CoreMotion
import Foundation

/// Wraps CoreMotion's accelerometer-derived device motion to produce one per-minute motion
/// variance value — the primary signal `SleepEngine.detectOnsetIndex` reasons about. All
/// processing happens on-device; no raw sample ever leaves this object.
@MainActor
final class MotionMonitor: ObservableObject {
    @Published private(set) var latestVariance: Double = 0
    @Published private(set) var isRunning = false

    private let manager = CMMotionManager()
    private var aggregator = VarianceAggregator()
    private var minuteTimer: Timer?

    /// 10 Hz is plenty of resolution for a "how still is the phone" stillness signal without
    /// draining the battery overnight.
    private let sampleInterval: TimeInterval = 1.0 / 10.0
    private let minuteLength: TimeInterval = 60

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !isRunning else { return }
        aggregator.reset()
        manager.deviceMotionUpdateInterval = sampleInterval
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let a = motion.userAcceleration
            let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            self.aggregator.add(magnitude)
        }
        minuteTimer = Timer.scheduledTimer(withTimeInterval: minuteLength, repeats: true) { [weak self] _ in
            self?.flushMinute()
        }
        isRunning = true
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        minuteTimer?.invalidate()
        minuteTimer = nil
        aggregator.reset()
        isRunning = false
    }

    private func flushMinute() {
        latestVariance = aggregator.variance ?? latestVariance
        aggregator.reset()
    }

    deinit {
        minuteTimer?.invalidate()
    }
}
