import SwiftUI

/// Midnight indigo-to-charcoal at night (the app's home look, since Driftwake lives on a
/// nightstand after dark); a softer dusk lavender-to-clay variant in light mode. Every shape
/// in the main UI chrome (ember, ring, halos) is circular or orbital — no straight edges or
/// rectangles there. Not the warm-gray/orange instrument look, not black/white/blue — a single
/// warm ember-orange accent is the only saturated color anywhere.
enum DriftwakeColor {
    static let bgTop = Color(light: Color(hex: 0xE9E3F6), dark: Color(hex: 0x0A0D28))
    static let bgBottom = Color(light: Color(hex: 0xF4EAE0), dark: Color(hex: 0x18191F))
    static var backdrop: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }

    static let ink = Color(light: Color(hex: 0x241F30), dark: Color(hex: 0xF4EFE8))
    static let inkMuted = Color(light: Color(hex: 0x6C6478), dark: Color(hex: 0xA5A0B2))
    static let panel = Color(light: Color(hex: 0xFFFFFF).opacity(0.55), dark: Color(hex: 0x181A2E).opacity(0.6))
    static let hairline = Color(light: Color(hex: 0x241F30).opacity(0.12), dark: Color(hex: 0xF4EFE8).opacity(0.12))

    static let ember = Color(hex: 0xFF8A3D)
    static let emberGlow = Color(hex: 0xFFC791)
    static let emberDeep = Color(hex: 0xC65A16)
    static let ringTrack = Color(light: Color(hex: 0x241F30).opacity(0.10), dark: Color(hex: 0xF4EFE8).opacity(0.10))
    static let lockout = Color(hex: 0x8E7CC3)
}

enum DriftwakeFont {
    static func title(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func headline(_ size: CGFloat = 17) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func value(_ size: CGFloat = 22) -> Font { .system(size: size, weight: .semibold, design: .monospaced) }
    static func caption(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func body(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .regular, design: .rounded) }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    init(light: Color, dark: Color) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
