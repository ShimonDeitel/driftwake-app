import SwiftUI

struct GrogginessView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var rating = 3
    @State private var logged = false
    @State private var showPaywall = false

    private var lastAnchorHours: Double {
        model.selectedProfile?.mode.totalHours ?? 8
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DriftwakeColor.backdrop.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Text("How groggy this morning?")
                                .font(DriftwakeFont.title(22))
                                .foregroundStyle(DriftwakeColor.ink)
                            Text("1 = very groggy · 5 = sharp and rested")
                                .font(.footnote)
                                .foregroundStyle(DriftwakeColor.inkMuted)
                        }
                        .padding(.top, 16)

                        HStack(spacing: 14) {
                            ForEach(1...5, id: \.self) { value in
                                Button {
                                    Haptics.click()
                                    rating = value
                                } label: {
                                    Circle()
                                        .fill(value == rating ? DriftwakeColor.ember : DriftwakeColor.panel)
                                        .overlay(Circle().strokeBorder(DriftwakeColor.hairline, lineWidth: value == rating ? 0 : 1))
                                        .overlay(
                                            Text("\(value)")
                                                .font(DriftwakeFont.value(16))
                                                .foregroundStyle(value == rating ? .white : DriftwakeColor.ink)
                                        )
                                        .frame(width: 48, height: 48)
                                }
                            }
                        }

                        if logged {
                            Text("Logged. Thanks for keeping Driftwake honest.")
                                .font(.footnote)
                                .foregroundStyle(DriftwakeColor.inkMuted)
                        } else {
                            Button("Log This Morning") {
                                Haptics.success()
                                model.logGrogginess(rating: rating, anchorDurationHours: lastAnchorHours)
                                logged = true
                            }
                            .prominentEmberButton()
                            .padding(.horizontal, 40)
                        }

                        aiInsightSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Morning Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .tint(DriftwakeColor.ember)
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    @ViewBuilder
    private var aiInsightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(DriftwakeColor.ember)
                Text("Nightly AI Insight").font(DriftwakeFont.headline(15)).foregroundStyle(DriftwakeColor.ink)
                Spacer()
            }

            if !store.isPro {
                HStack {
                    Text("Pro finds the pattern in your last 14 nights and suggests a specific anchor to try.")
                        .font(.footnote).foregroundStyle(DriftwakeColor.inkMuted)
                    Spacer(minLength: 8)
                    Button("Unlock") { showPaywall = true }
                        .font(DriftwakeFont.caption(12))
                        .foregroundStyle(DriftwakeColor.ember)
                }
            } else if model.aiInsightLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reading your last 14 nights…").font(.footnote).foregroundStyle(DriftwakeColor.inkMuted)
                }
            } else if let insight = model.aiInsight {
                Text(insight).font(.subheadline).foregroundStyle(DriftwakeColor.ink)
            } else if let error = model.aiInsightError {
                Text(error).font(.footnote).foregroundStyle(DriftwakeColor.inkMuted)
            }

            if store.isPro {
                Button(model.aiInsight == nil ? "Get Tonight's Insight" : "Refresh Insight") {
                    Task { await model.requestNightlyInsight() }
                }
                .haloButton()
                .disabled(model.aiInsightLoading)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DriftwakeColor.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(DriftwakeColor.hairline, lineWidth: 1))
    }
}
