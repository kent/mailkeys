import Foundation

/// Counts shortcuts MailKeys performed in Mail and estimates the time they saved
/// compared with doing the same thing with a mouse or trackpad.
///
/// Estimates use the Keystroke-Level Model (Card, Moran & Newell): moving a hand
/// to the mouse 0.4 s, pointing 1.1 s, clicking 0.2 s, one keystroke 0.28 s.
/// Only the key name and a count are stored. No message data is recorded.
struct UsageStats: Equatable {
    static let secondsSavedPerUse: [String: Double] = [
        // Reach for the mouse, point, click (1.7 s) versus one keystroke (0.28 s).
        "j": 1.42, "k": 1.42, "r": 1.42, "a": 1.42, "f": 1.42, "c": 1.42, "/": 1.42,
        // Reach, click the message, then point at and click Archive (3.0 s) versus
        // pointing at the message, which hovering still needs, plus one keystroke (1.38 s).
        "e": 1.62,
    ]

    private(set) var counts: [String: Int]

    init(counts: [String: Int] = [:]) {
        self.counts = counts.filter { Self.secondsSavedPerUse[$0.key] != nil && $0.value > 0 }
    }

    mutating func record(_ key: String) {
        let key = key.lowercased()
        guard Self.secondsSavedPerUse[key] != nil else { return }
        counts[key, default: 0] += 1
    }

    var totalUses: Int { counts.values.reduce(0, +) }

    /// Total estimated time saved, rounded to the nearest second.
    var secondsSaved: Int {
        Int(counts.reduce(0.0) { $0 + Double($1.value) * (Self.secondsSavedPerUse[$1.key] ?? 0) }.rounded())
    }

    /// The most used shortcut. Ties go to the alphabetically first key so the result is stable.
    var mostUsed: (key: String, count: Int)? {
        counts.min { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    static func format(seconds: Int) -> String {
        let hours = seconds / 3600, minutes = seconds % 3600 / 60, remainder = seconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m \(remainder)s" }
        if minutes > 0 { return "\(minutes)m \(remainder)s" }
        return "\(remainder)s"
    }
}
