import SwiftUI

struct AnchorProfilesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var showEditor = false
    @State private var editingProfile: AnchorProfile?
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.profiles) { profile in
                        Button {
                            Haptics.click()
                            model.selectedProfileID = profile.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name).font(DriftwakeFont.headline(15)).foregroundStyle(DriftwakeColor.ink)
                                    Text(profile.mode.label).font(DriftwakeFont.value(13)).foregroundStyle(DriftwakeColor.inkMuted)
                                }
                                Spacer()
                                if profile.id == model.selectedProfileID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DriftwakeColor.ember)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Edit") { editingProfile = profile; showEditor = true }
                                .tint(DriftwakeColor.ember)
                            if model.profiles.count > 1 {
                                Button("Delete", role: .destructive) { model.deleteProfile(profile) }
                            }
                        }
                    }
                } footer: {
                    Text(store.isPro
                         ? "Save as many anchors as you like — weeknight, nap, jet lag."
                         : "Free keeps one fixed anchor. Upgrade to Pro for multiple saved anchors and automatic onset detection.")
                }

                Section {
                    Button {
                        if model.canAddProfile(isPro: store.isPro) {
                            editingProfile = nil
                            showEditor = true
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        Label("Add Anchor", systemImage: model.canAddProfile(isPro: store.isPro) ? "plus.circle.fill" : "lock.fill")
                    }
                }
            }
            .navigationTitle("Anchor Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .tint(DriftwakeColor.ember)
            .sheet(isPresented: $showEditor) {
                AnchorEditorView(existing: editingProfile)
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }
}

private struct AnchorEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let existing: AnchorProfile?

    @State private var name: String
    @State private var useCycles: Bool
    @State private var hours: Double
    @State private var cycles: Int

    init(existing: AnchorProfile?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "New Anchor")
        switch existing?.mode {
        case .some(.cycles(let c)):
            _useCycles = State(initialValue: true)
            _cycles = State(initialValue: c)
            _hours = State(initialValue: 8)
        case .some(.hours(let h)):
            _useCycles = State(initialValue: false)
            _hours = State(initialValue: h)
            _cycles = State(initialValue: 5)
        case .none:
            _useCycles = State(initialValue: false)
            _hours = State(initialValue: 8)
            _cycles = State(initialValue: 5)
        }
    }

    private var mode: AnchorDurationMode {
        useCycles ? AnchorDurationMode.clampedCycles(cycles) : AnchorDurationMode.clampedHours(hours)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Anchor name", text: $name)
                }
                Section("Duration") {
                    Picker("Mode", selection: $useCycles) {
                        Text("Hours").tag(false)
                        Text("Sleep Cycles").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if useCycles {
                        Stepper(value: $cycles, in: AnchorDurationMode.minCycles...AnchorDurationMode.maxCycles) {
                            Text("\(cycles) cycles (\(mode.label))")
                        }
                    } else {
                        Stepper(value: $hours, in: AnchorDurationMode.minHours...AnchorDurationMode.maxHours, step: 0.5) {
                            Text(mode.label)
                        }
                    }
                }
            }
            .dismissKeyboardOnTap()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existing == nil ? "Add Anchor" : "Edit Anchor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if let existing {
                            model.updateProfile(existing, name: name, mode: mode)
                        } else {
                            model.addProfile(name: name, mode: mode)
                        }
                        dismiss()
                    }
                }
            }
            .tint(DriftwakeColor.ember)
        }
    }
}
