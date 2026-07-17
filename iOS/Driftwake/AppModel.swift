import Foundation
import SwiftUI

/// Owns every piece of session state: saved anchor profiles, the grogginess log, and the
/// live session phase (idle / watching / locked / alarming / snoozed). Motion/mic monitors and
/// notification scheduling are driven from here so views stay dumb.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var profiles: [AnchorProfile] = []
    @Published var selectedProfileID: UUID?
    @Published private(set) var grogginessLog: [GrogginessEntry] = []

    @Published private(set) var phase: SessionPhase = .idle
    @Published private(set) var lastSnoozeDecision: SnoozeDecision?

    @Published var aiInsight: String?
    @Published var aiInsightError: String?
    @Published var aiInsightLoading = false

    weak var store: Store?

    let motionMonitor = MotionMonitor()
    let micMonitor = MicMonitor()

    private var tickTimer: Timer?
    private var minuteVariances: [Double] = []
    private var snoozeWindowVariances: [Double] = []

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let profiles = "driftwake.profiles"
        static let selected = "driftwake.selectedProfile"
        static let log = "driftwake.grogginessLog"
    }

    init() {
        loadProfiles()
        loadLog()
        NotificationScheduler.registerCategories()
    }

    // MARK: Profiles

    var selectedProfile: AnchorProfile? {
        profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    /// Free tier keeps exactly one profile; Pro can save several.
    func canAddProfile(isPro: Bool) -> Bool {
        isPro || profiles.isEmpty
    }

    @discardableResult
    func addProfile(name: String, mode: AnchorDurationMode) -> Bool {
        guard canAddProfile(isPro: store?.isPro == true) else { return false }
        let profile = AnchorProfile(name: name, mode: mode)
        profiles.append(profile)
        selectedProfileID = profile.id
        saveProfiles()
        return true
    }

    func updateProfile(_ profile: AnchorProfile, name: String, mode: AnchorDurationMode) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profile
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = trimmed.isEmpty ? profile.name : trimmed
        updated.mode = mode
        profiles[index] = updated
        saveProfiles()
    }

    func deleteProfile(_ profile: AnchorProfile) {
        guard profiles.count > 1 else { return } // always keep at least one anchor
        profiles.removeAll { $0.id == profile.id }
        if selectedProfileID == profile.id { selectedProfileID = profiles.first?.id }
        saveProfiles()
    }

    private func loadProfiles() {
        if let data = defaults.data(forKey: Keys.profiles),
           let decoded = try? JSONDecoder().decode([AnchorProfile].self, from: data),
           !decoded.isEmpty {
            profiles = decoded
        } else {
            profiles = [AnchorProfile(name: "Default", mode: .hours(8))]
        }
        if let idString = defaults.string(forKey: Keys.selected), let id = UUID(uuidString: idString),
           profiles.contains(where: { $0.id == id }) {
            selectedProfileID = id
        } else {
            selectedProfileID = profiles.first?.id
        }
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: Keys.profiles) }
        defaults.set(selectedProfileID?.uuidString, forKey: Keys.selected)
    }

    // MARK: Grogginess log

    func logGrogginess(rating: Int, anchorDurationHours: Double) {
        let entry = GrogginessEntry(date: Date(), anchorDurationHours: anchorDurationHours, rating: rating)
        grogginessLog.append(entry)
        saveLog()
    }

    private func loadLog() {
        guard let data = defaults.data(forKey: Keys.log),
              let decoded = try? JSONDecoder().decode([GrogginessEntry].self, from: data) else { return }
        grogginessLog = decoded
    }

    private func saveLog() {
        if let data = try? JSONEncoder().encode(grogginessLog) { defaults.set(data, forKey: Keys.log) }
    }

    // MARK: Session — manual anchor (Free tier)

    /// "I'm about to sleep" — the tap itself IS the onset for the free, manual-tagging tier.
    func tapAsleepNow() {
        guard let profile = selectedProfile else { return }
        let now = Date()
        let wake = SleepEngine.wakeDate(from: now, mode: profile.mode)
        phase = .locked(onsetAt: now, wakeAt: wake, mode: profile.mode)
        Task { _ = await NotificationScheduler.requestAuthorization() }
        NotificationScheduler.scheduleWakeAlarm(at: wake, mode: profile.mode)
        Haptics.success()
    }

    // MARK: Session — automatic detection (Pro)

    func startWatching() {
        guard let profile = selectedProfile, store?.isPro == true else { return }
        let now = Date()
        minuteVariances = []
        phase = .watching(startedAt: now, mode: profile.mode)
        motionMonitor.start()
        micMonitor.start()
        Task { _ = await NotificationScheduler.requestAuthorization() }
        startTicking()
    }

    func cancelSession() {
        motionMonitor.stop()
        micMonitor.stop()
        stopTicking()
        NotificationScheduler.cancelWakeAlarm()
        phase = .idle
    }

    private func startTicking() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onMinuteTick() }
        }
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func onMinuteTick() {
        guard case .watching(let startedAt, let mode) = phase else { return }
        let combined = SleepEngine.combinedVariance(motion: motionMonitor.latestVariance, mic: micMonitor.latestVariance)
        minuteVariances.append(combined)
        guard let onsetIndex = SleepEngine.detectOnsetIndex(variances: minuteVariances) else { return }
        let onsetAt = startedAt.addingTimeInterval(Double(onsetIndex) * 60)
        let wake = SleepEngine.wakeDate(from: onsetAt, mode: mode)
        phase = .locked(onsetAt: onsetAt, wakeAt: wake, mode: mode)
        NotificationScheduler.scheduleWakeAlarm(at: wake, mode: mode)
        motionMonitor.stop()
        micMonitor.stop()
        stopTicking()
        Haptics.success()
    }

    // MARK: Alarm + snooze (called from NotificationDelegate)

    func handleAlarmFired() {
        snoozeWindowVariances = []
        switch phase {
        case .locked(_, let wakeAt, let mode), .snoozed(let wakeAt, let mode):
            phase = .alarming(wakeAt: wakeAt, mode: mode)
        default:
            if let profile = selectedProfile {
                phase = .alarming(wakeAt: Date(), mode: profile.mode)
            }
        }
    }

    /// Samples the current combined variance into the snooze window and re-evaluates the
    /// quirky lock/allow decision. Called on a short interval while the alarm screen is up.
    @discardableResult
    func sampleSnoozeWindow() -> SnoozeDecision {
        let combined = SleepEngine.combinedVariance(motion: motionMonitor.latestVariance, mic: micMonitor.latestVariance)
        snoozeWindowVariances.append(combined)
        if snoozeWindowVariances.count > 12 {
            snoozeWindowVariances.removeFirst(snoozeWindowVariances.count - 12)
        }
        let decision = SnoozeEvaluator.evaluate(snoozeWindowVariances: snoozeWindowVariances)
        lastSnoozeDecision = decision
        return decision
    }

    func handleSnoozeTapped() {
        guard case .alarming(_, let mode) = phase else { return }
        switch sampleSnoozeWindow() {
        case .allowed:
            let until = Date().addingTimeInterval(9 * 60)
            phase = .snoozed(until: until, mode: mode)
            NotificationScheduler.scheduleWakeAlarm(at: until, mode: mode)
        case .lockedOut:
            break // stays in .alarming; UI reflects lastSnoozeDecision's explanation.
        }
    }

    func dismissAlarm() {
        NotificationScheduler.cancelWakeAlarm()
        phase = .idle
        lastSnoozeDecision = nil
    }

    // MARK: AI insight (Pro)

    func requestNightlyInsight() async {
        guard store?.isPro == true else { return }
        aiInsightLoading = true
        aiInsightError = nil
        let result = await AIProxyClient.nightlyInsight(entries: grogginessLog)
        aiInsightLoading = false
        switch result {
        case .success(let text):
            aiInsight = text
        case .failure(AIProxyClient.ClientError.notEnoughHistory):
            aiInsightError = "Log a few more mornings first — Driftwake needs at least 3 nights of grogginess ratings to spot a pattern."
        case .failure:
            aiInsightError = "The insight service is briefly unavailable. Your data is safe on-device — try again in a bit."
        }
    }

    // MARK: Data management

    func eraseAllData() {
        cancelSession()
        profiles = [AnchorProfile(name: "Default", mode: .hours(8))]
        selectedProfileID = profiles.first?.id
        grogginessLog = []
        aiInsight = nil
        aiInsightError = nil
        saveProfiles()
        saveLog()
    }

    deinit {
        tickTimer?.invalidate()
    }
}
