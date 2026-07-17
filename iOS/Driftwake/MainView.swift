import SwiftUI

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: Store

    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var showProfiles = false
    @State private var showGrogginess = false
    @State private var snoozeTicker: Timer?

    var body: some View {
        ZStack {
            DriftwakeColor.backdrop.ignoresSafeArea()
            VStack(spacing: 26) {
                header
                Spacer(minLength: 0)
                emberStack
                Spacer(minLength: 0)
                statusStrip
                controls
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showProfiles) { AnchorProfilesView() }
        .sheet(isPresented: $showGrogginess) { GrogginessView() }
        .onChange(of: model.phase) { _, newPhase in
            if case .alarming = newPhase {
                startSnoozeTicker()
            } else {
                stopSnoozeTicker()
            }
        }
        .onDisappear { stopSnoozeTicker() }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Driftwake")
                .font(DriftwakeFont.title(24))
                .foregroundStyle(DriftwakeColor.ink)
            Spacer()
            Button { showGrogginess = true } label: {
                Image(systemName: "text.bubble")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DriftwakeColor.inkMuted)
            }
            .accessibilityLabel("Log grogginess")
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DriftwakeColor.inkMuted)
            }
            .accessibilityIdentifier("settings-button")
            .accessibilityLabel("Settings")
        }
    }

    // MARK: Ember + ring

    private var emberStack: some View {
        VStack(spacing: 22) {
            ZStack {
                if case .locked(let onsetAt, let wakeAt, _) = model.phase {
                    CountdownRingView(onsetAt: onsetAt, wakeAt: wakeAt)
                } else if case .snoozed = model.phase {
                    CountdownRingView(onsetAt: Date().addingTimeInterval(-9 * 60), wakeAt: model.snoozeUntilDateOrNow)
                }
                EmberView(locked: isOnsetLocked)
            }
            .frame(width: 260, height: 260)

            Text(phaseHeadline)
                .font(DriftwakeFont.headline(16))
                .foregroundStyle(DriftwakeColor.ink)
                .multilineTextAlignment(.center)
            if let subtext = phaseSubtext {
                Text(subtext)
                    .font(.footnote)
                    .foregroundStyle(DriftwakeColor.inkMuted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var isOnsetLocked: Bool {
        switch model.phase {
        case .locked, .alarming, .snoozed: return true
        case .idle, .watching: return false
        }
    }

    private var phaseHeadline: String {
        switch model.phase {
        case .idle:
            return "Ready when you are"
        case .watching:
            return "Watching for sleep onset…"
        case .locked(_, let wakeAt, _):
            return "Onset locked — waking at \(Self.timeFormatter.string(from: wakeAt))"
        case .alarming:
            return "Time to wake up"
        case .snoozed(let until, _):
            return "Snoozed until \(Self.timeFormatter.string(from: until))"
        }
    }

    private var phaseSubtext: String? {
        switch model.phase {
        case .idle:
            return "Pick an anchor below, then start your night."
        case .watching(let startedAt, _):
            let minutes = max(0, Int(Date().timeIntervalSince(startedAt) / 60))
            return "\(minutes) min of motion + room sound sampled so far."
        case .locked(let onsetAt, _, let mode):
            return "Fell asleep around \(Self.timeFormatter.string(from: onsetAt)) · \(mode.label) anchor"
        case .alarming:
            return nil
        case .snoozed:
            return "Driftwake will check again shortly."
        }
    }

    // MARK: Status strip (selected anchor)

    private var statusStrip: some View {
        HaloStrip {
            Image(systemName: "moon.circle.fill")
                .foregroundStyle(DriftwakeColor.ember)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.selectedProfile?.name ?? "No anchor")
                    .font(DriftwakeFont.headline(14))
                    .foregroundStyle(DriftwakeColor.ink)
                Text(model.selectedProfile?.mode.label ?? "—")
                    .font(DriftwakeFont.value(13))
                    .foregroundStyle(DriftwakeColor.inkMuted)
            }
            Spacer(minLength: 12)
            Button("Anchors") { showProfiles = true }
                .font(DriftwakeFont.caption(12))
                .foregroundStyle(DriftwakeColor.ember)
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        switch model.phase {
        case .idle:
            VStack(spacing: 12) {
                Button("I'm about to sleep") {
                    Haptics.tap()
                    model.tapAsleepNow()
                }
                .prominentEmberButton()
                .accessibilityIdentifier("sleep-now-button")

                Button {
                    if store.isPro {
                        Haptics.tap()
                        model.startWatching()
                    } else {
                        showPaywall = true
                    }
                } label: {
                    HStack {
                        Text("Start Automatic Detection")
                        if !store.isPro {
                            Image(systemName: "lock.fill").font(.caption)
                        }
                    }
                }
                .haloButton()
                .accessibilityIdentifier("auto-detect-button")
            }
        case .watching, .locked:
            Button("Cancel Tonight") {
                Haptics.warning()
                model.cancelSession()
            }
            .haloButton()
        case .alarming:
            VStack(spacing: 12) {
                Button("Stop Alarm") {
                    Haptics.success()
                    model.dismissAlarm()
                    showGrogginess = true
                }
                .prominentEmberButton()

                if let decision = model.lastSnoozeDecision, case .lockedOut(let reason) = decision {
                    VStack(spacing: 6) {
                        Button("Snooze") {}
                            .haloButton()
                            .disabled(true)
                            .opacity(0.4)
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(DriftwakeColor.lockout)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Button("Snooze (second chance)") {
                        Haptics.tap()
                        model.handleSnoozeTapped()
                    }
                    .haloButton()
                }
            }
        case .snoozed:
            Button("Cancel Tonight") {
                Haptics.warning()
                model.cancelSession()
            }
            .haloButton()
        }
    }

    private func startSnoozeTicker() {
        stopSnoozeTicker()
        model.sampleSnoozeWindow()
        snoozeTicker = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor in model.sampleSnoozeWindow() }
        }
    }

    private func stopSnoozeTicker() {
        snoozeTicker?.invalidate()
        snoozeTicker = nil
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()
}

extension AppModel {
    /// Best-effort wake target for the ring while snoozed (used only to draw the ring's
    /// progress — the authoritative alarm is the scheduled notification).
    var snoozeUntilDateOrNow: Date {
        if case .snoozed(let until, _) = phase { return until }
        return Date()
    }
}
