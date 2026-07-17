import Foundation

/// The two ways an anchor duration can be expressed: plain hours, or a whole number of
/// 90-minute sleep cycles. `totalHours` is the single canonical value everything else works in.
enum AnchorDurationMode: Equatable {
    case hours(Double)
    case cycles(Int)

    static let minHours: Double = 3.0
    static let maxHours: Double = 10.0
    static let minCycles: Int = 2
    static let maxCycles: Int = 7
    static let hoursPerCycle: Double = 1.5

    var totalHours: Double {
        switch self {
        case .hours(let h): return h
        case .cycles(let c): return Double(c) * Self.hoursPerCycle
        }
    }

    var label: String {
        switch self {
        case .hours(let h):
            return h.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(h))h"
                : String(format: "%.1fh", h)
        case .cycles(let c):
            return "\(c) cycle\(c == 1 ? "" : "s") (\(AnchorDurationMode.formattedHours(Double(c) * Self.hoursPerCycle)))"
        }
    }

    private static func formattedHours(_ h: Double) -> String {
        h.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(h))h" : String(format: "%.1fh", h)
    }

    /// Clamp a raw hours value into the range the anchor picker supports.
    static func clampedHours(_ h: Double) -> AnchorDurationMode {
        .hours(min(max(h, minHours), maxHours))
    }

    /// Clamp a raw cycle count into the range the anchor picker supports.
    static func clampedCycles(_ c: Int) -> AnchorDurationMode {
        .cycles(min(max(c, minCycles), maxCycles))
    }
}

extension AnchorDurationMode: Codable {
    private enum CodingKeys: String, CodingKey { case kind, value }
    private enum Kind: String, Codable { case hours, cycles }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .hours:
            self = .hours(try container.decode(Double.self, forKey: .value))
        case .cycles:
            self = .cycles(try container.decode(Int.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hours(let h):
            try container.encode(Kind.hours, forKey: .kind)
            try container.encode(h, forKey: .value)
        case .cycles(let c):
            try container.encode(Kind.cycles, forKey: .kind)
            try container.encode(c, forKey: .value)
        }
    }
}

/// A saved wake-anchor. Free tier keeps exactly one; Pro can save several.
struct AnchorProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var mode: AnchorDurationMode
    var createdAt: Date

    init(id: UUID = UUID(), name: String, mode: AnchorDurationMode, createdAt: Date = Date()) {
        self.id = id
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed.isEmpty ? "Anchor" : trimmed
        self.mode = mode
        self.createdAt = createdAt
    }
}

/// One morning's self-rated grogginess tied to the anchor duration used that night.
struct GrogginessEntry: Codable, Equatable {
    let date: Date
    let anchorDurationHours: Double
    let rating: Int // 1 (very groggy) ... 5 (sharp and rested)
}

/// Helpers over the grogginess history — the same 14-day trim the AI insight prompt uses.
enum GrogginessLog {
    static func lastDays(_ entries: [GrogginessEntry], days: Int = 14, referenceDate: Date = Date()) -> [GrogginessEntry] {
        let cutoff = referenceDate.addingTimeInterval(-Double(days) * 86_400)
        return entries
            .filter { $0.date >= cutoff && $0.date <= referenceDate }
            .sorted { $0.date < $1.date }
    }
}

/// The whole-app session state machine.
enum SessionPhase: Equatable {
    /// Nothing running — home screen, ember flickering idly.
    case idle
    /// Pro automatic detection armed; watching motion/mic for onset. Ember still flickering.
    case watching(startedAt: Date, mode: AnchorDurationMode)
    /// Onset confirmed (manual tap or automatic detection). Ember holds still, ring traces.
    case locked(onsetAt: Date, wakeAt: Date, mode: AnchorDurationMode)
    /// Wake time reached — alarm is firing.
    case alarming(wakeAt: Date, mode: AnchorDurationMode)
    /// Second-chance snooze granted; counting down to the next wake check.
    case snoozed(until: Date, mode: AnchorDurationMode)
}

/// Outcome of the quirky second-chance-snooze check.
enum SnoozeDecision: Equatable {
    case allowed
    case lockedOut(reason: String)
}
