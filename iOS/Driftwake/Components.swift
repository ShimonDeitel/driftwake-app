import SwiftUI
import UIKit

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func click() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - Buttons

struct EmberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DriftwakeFont.headline())
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(DriftwakeColor.ember, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct HaloButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DriftwakeFont.headline(15))
            .foregroundStyle(DriftwakeColor.ink)
            .padding(.vertical, 13)
            .padding(.horizontal, 20)
            .background(DriftwakeColor.panel, in: Capsule())
            .overlay(Capsule().strokeBorder(DriftwakeColor.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    func prominentEmberButton() -> some View { buttonStyle(EmberButtonStyle()) }
    func haloButton() -> some View { buttonStyle(HaloButtonStyle()) }
}

/// A rounded, pill-shaped info strip (still no straight-edged rectangle — capsule ends are
/// two half-circles).
struct HaloStrip<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 10) { content }
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(DriftwakeColor.panel, in: Capsule())
            .overlay(Capsule().strokeBorder(DriftwakeColor.hairline, lineWidth: 1))
    }
}

// MARK: - The animation hook

/// The ember/star at the heart of the main screen. It flickers continuously — driven by
/// layered, never-repeating sine waves via `TimelineView(.animation)` — while Driftwake is
/// watching for sleep onset. The instant onset locks, the flicker stops (the ember simply
/// renders its steady state every frame), and a distinct spring-driven pulse marks the
/// transition so the moment reads as a deliberate "lock", not just an animation stopping.
struct EmberView: View {
    var locked: Bool
    var diameter: CGFloat = 96

    @State private var lockPulse: CGFloat = 1.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let flicker = locked ? 1.0 : emberFlicker(t)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let coreRadius = diameter / 2 * (0.68 + 0.16 * flicker)
                let glowRadius = coreRadius * (locked ? 2.1 : 1.5 + 0.35 * flicker)

                var haloContext = context
                haloContext.opacity = locked ? 0.5 : 0.22 + 0.22 * flicker
                let haloRect = CGRect(x: center.x - glowRadius, y: center.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)
                haloContext.fill(
                    Path(ellipseIn: haloRect),
                    with: .radialGradient(
                        Gradient(colors: [DriftwakeColor.ember.opacity(0.85), DriftwakeColor.ember.opacity(0)]),
                        center: center, startRadius: 0, endRadius: glowRadius
                    )
                )

                let coreRect = CGRect(x: center.x - coreRadius, y: center.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)
                context.fill(
                    Path(ellipseIn: coreRect),
                    with: .radialGradient(
                        Gradient(colors: [DriftwakeColor.emberGlow, DriftwakeColor.ember, DriftwakeColor.emberDeep]),
                        center: center, startRadius: 0, endRadius: coreRadius
                    )
                )
            }
            .frame(width: diameter * 2.4, height: diameter * 2.4)
        }
        .scaleEffect(lockPulse)
        .onChange(of: locked) { _, isLocked in
            guard isLocked else { return }
            withAnimation(.interpolatingSpring(stiffness: 220, damping: 9)) { lockPulse = 1.32 }
            withAnimation(.easeOut(duration: 0.45).delay(0.12)) { lockPulse = 1.0 }
        }
    }

    /// Three layered sine waves at incommensurate frequencies so the pre-onset flicker never
    /// repeats in any short window — reads as alive, not a looping GIF.
    private func emberFlicker(_ t: TimeInterval) -> Double {
        let a = sin(t * 2.3) * 0.5 + 0.5
        let b = sin(t * 5.1 + 1.3) * 0.5 + 0.5
        let c = sin(t * 0.7 + 0.4) * 0.5 + 0.5
        return a * 0.5 + b * 0.3 + c * 0.2
    }
}

/// A thin, Canvas-drawn arc that traces in real time from onset toward the anchored wake
/// point. Time-driven via `TimelineView`, not a stored progress value, so it stays accurate
/// even if the view was recreated.
struct CountdownRingView: View {
    let onsetAt: Date
    let wakeAt: Date
    var diameter: CGFloat = 250
    var lineWidth: CGFloat = 9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let total = wakeAt.timeIntervalSince(onsetAt)
            let elapsed = timeline.date.timeIntervalSince(onsetAt)
            let progress = total > 0 ? min(max(elapsed / total, 0), 1) : 0
            Canvas { context, size in
                let radius = min(size.width, size.height) / 2 - lineWidth / 2
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                var track = Path()
                track.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
                context.stroke(track, with: .color(DriftwakeColor.ringTrack), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                var arc = Path()
                let endAngle = -90 + 360 * progress
                arc.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(endAngle), clockwise: false)
                context.stroke(
                    arc,
                    with: .linearGradient(
                        Gradient(colors: [DriftwakeColor.ember, DriftwakeColor.emberGlow]),
                        startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
        }
        .frame(width: diameter, height: diameter)
    }
}
