import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @AppStorage("driftwake.theme") private var themeRaw = AppTheme.system.rawValue

    @State private var showPaywall = false
    @State private var showEraseConfirm = false
    @State private var restoreMessage: String?

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Driftwake \(v)"
    }

    var body: some View {
        NavigationStack {
            Form {
                proSection
                appearanceSection
                howItDetectsSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .tint(DriftwakeColor.emberDeep)
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .alert("Erase All Driftwake Data?", isPresented: $showEraseConfirm) {
                Button("Erase", role: .destructive) {
                    model.eraseAllData()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes every saved anchor and your grogginess history. Driftwake keeps no data anywhere else.")
            }
        }
    }

    @ViewBuilder
    private var proSection: some View {
        Section {
            if store.isPro {
                HStack {
                    Label("Driftwake Pro", systemImage: "flame.fill")
                    Spacer()
                    Text("Active").foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Haptics.tap(); showPaywall = true
                } label: {
                    HStack {
                        Label("Get Driftwake Pro", systemImage: "flame.fill")
                        Spacer()
                        Text("\(store.displayPrice)/mo").foregroundStyle(.secondary)
                    }
                }
                Button("Restore Purchase") {
                    Task {
                        await store.restore()
                        restoreMessage = store.isPro ? "Restored." : "No previous purchase found."
                    }
                }
                if let restoreMessage {
                    Text(restoreMessage).font(.footnote).foregroundStyle(.secondary)
                }
            }
        } footer: {
            if !store.isPro {
                Text("Automatic onset detection, multiple anchor profiles, and the nightly AI insight.")
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $themeRaw) {
                ForEach(AppTheme.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var howItDetectsSection: some View {
        Section {
            DisclosureGroup("How Driftwake detects sleep onset") {
                Text("Driftwake watches your phone's motion sensor and microphone (never recording audio — only its metered loudness) for a sustained drop in variance: about 8 minutes of near-stillness and near-quiet in a row. Onset is then back-dated to when that stillness began, and your anchor duration counts forward from that moment, not from when you tapped Start. Everything is computed on-device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            DisclosureGroup("Why automatic detection needs the app open") {
                Text("iOS suspends background apps aggressively. Driftwake uses the same background-audio technique sleep-tracking and white-noise apps rely on to keep sampling overnight, but if the system still suspends it, detection stops — the free \"I'm about to sleep\" tap always works as a reliable fallback.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dataSection: some View {
        Section {
            Button("Erase All Data", role: .destructive) { showEraseConfirm = true }
        } header: {
            Text("Data & Privacy")
        } footer: {
            Text("Motion and microphone data are analyzed on-device only, never recorded or uploaded. \(model.grogginessLog.count) grogginess entries are saved locally. The nightly AI insight sends only your anchor-duration and rating numbers — no audio, no motion data, no identity — to a stateless proxy that keeps no server-side history.")
        }
    }

    private var aboutSection: some View {
        Section {
            Link("Privacy Policy", destination: URL(string: "https://shimondeitel.github.io/driftwake-site/privacy.html")!)
            Link("Terms of Use", destination: URL(string: "https://shimondeitel.github.io/driftwake-site/terms.html")!)
        } footer: {
            Text(version).frame(maxWidth: .infinity, alignment: .center).padding(.top, 4)
        }
    }
}
