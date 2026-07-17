import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var restoreMessage: String?

    private let benefits: [(String, String, String)] = [
        ("moon.stars.fill", "Automatic onset detection", "No more tapping a button — Driftwake watches motion and room sound and locks onset the moment you actually drift off."),
        ("circle.grid.cross.fill", "Multiple anchor profiles", "Save a weeknight anchor, a nap anchor, a jet-lag anchor — recall any of them with one tap."),
        ("sparkles", "Nightly AI insight", "Your last 14 nights of grogginess ratings, read for a pattern, with one plain-language suggestion for tonight.")
    ]

    var body: some View {
        ZStack {
            DriftwakeColor.backdrop.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        Circle()
                            .fill(DriftwakeColor.ember.opacity(0.16))
                            .frame(width: 64, height: 64)
                            .overlay(
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(DriftwakeColor.ember)
                            )
                        Text("Driftwake Pro").font(DriftwakeFont.title(28))
                            .foregroundStyle(DriftwakeColor.ink)
                        Text("\(store.displayPrice) / month. Cancel anytime.")
                            .font(.subheadline).foregroundStyle(DriftwakeColor.inkMuted)
                    }
                    .padding(.top, 28)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(benefits, id: \.0) { item in
                            HStack(alignment: .top, spacing: 14) {
                                Circle()
                                    .fill(DriftwakeColor.ember.opacity(0.14))
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Image(systemName: item.0)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(DriftwakeColor.ember)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.1).font(DriftwakeFont.headline(16))
                                        .foregroundStyle(DriftwakeColor.ink)
                                    Text(item.2).font(.subheadline).foregroundStyle(DriftwakeColor.inkMuted)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(18)
                    .background(DriftwakeColor.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(DriftwakeColor.hairline, lineWidth: 1)
                    )
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        Button { Task { await buy() } } label: {
                            HStack {
                                if working { ProgressView().tint(.white) }
                                Text(working ? "Starting…" : "Start Driftwake Pro · \(store.displayPrice)/mo")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .prominentEmberButton()
                        .accessibilityIdentifier("paywall-subscribe")
                        .disabled(working)

                        Button("Restore Purchase") { Task { await restore() } }
                            .font(.subheadline).tint(DriftwakeColor.inkMuted)

                        if let restoreMessage {
                            Text(restoreMessage).font(.footnote).foregroundStyle(DriftwakeColor.inkMuted)
                        }

                        Text("Auto-renewable subscription, billed monthly to your Apple ID. Manage or cancel anytime in Settings.")
                            .font(.footnote).foregroundStyle(DriftwakeColor.inkMuted)
                            .multilineTextAlignment(.center).padding(.top, 4)
                    }
                    .padding(.horizontal).padding(.bottom, 30)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2)
                    .foregroundStyle(DriftwakeColor.inkMuted).padding()
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("paywall-close")
        }
        .onChange(of: store.isPro) { _, newValue in if newValue { dismiss() } }
    }

    private func buy() async {
        working = true
        let ok = await store.purchase()
        working = false
        if ok { Haptics.success(); dismiss() }
    }

    private func restore() async {
        await store.restore()
        if store.isPro { Haptics.success(); dismiss() }
        else { restoreMessage = "No previous purchase found on this Apple ID." }
    }
}
