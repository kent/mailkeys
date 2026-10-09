// Small state machines that keep key handling fast without trusting stale state.

import Foundation

// A cached validation can only be reused after a fresh focus/window snapshot.
// Changing either identity or explicitly invalidating it requires revalidation.
struct FocusSnapshotCache<Identity: Equatable, Value> {
    private var entry: (window: Identity, focus: Identity, value: Value)?

    func value(window: Identity, focus: Identity) -> Value? {
        guard let entry, entry.window == window, entry.focus == focus else { return nil }
        return entry.value
    }

    mutating func store(_ value: Value, window: Identity, focus: Identity) {
        entry = (window, focus, value)
    }

    mutating func invalidate() { entry = nil }
}

/// Tracks a held J or K. The glide starts after a short delay, runs at a fixed rate, and stops the
/// moment the key is released, a modifier is pressed, or Mail or the message list loses focus.
struct NavigationRepeatState {
    static let initialDelay: TimeInterval = 0.18
    static let interval: TimeInterval = 1.0 / 30.0
    private(set) var key: Int64?

    mutating func begin(_ key: Int64) { self.key = key }
    mutating func stop() { key = nil }
    @discardableResult mutating func release(_ key: Int64) -> Bool {
        guard self.key == key else { return false }
        stop()
        return true
    }

    func canRepeat(keyIsDown: Bool, mailIsActive: Bool, listIsFocused: Bool, hasModifiers: Bool) -> Bool {
        key != nil && keyIsDown && mailIsActive && listIsFocused && !hasModifiers
    }
}
