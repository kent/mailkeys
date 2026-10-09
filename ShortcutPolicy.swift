// The rules for when a shortcut may act, kept free of AppKit and Mail so they can be tested.
//
// Every decision here leans the same way: when in doubt, let the key through as
// ordinary typing. A missed shortcut is a small annoyance. An eaten letter in an
// email is not.

import Foundation
import CoreGraphics

/// A Gmail key mapped to the Mail keyboard shortcut that performs the same action.
struct Shortcut {
    let name: String
    let keyCode: CGKeyCode
    let flags: CGEventFlags
    let repeats: Bool
}

enum ShortcutPolicy {
    /// Where the pointer is when E is pressed: over a message row, over the list between rows, or elsewhere.
    enum HoverLocation { case message, listGap, elsewhere }
    /// What E should archive: the hovered message, the selected one, nothing, or pass the key through.
    enum ArchiveTarget { case hovered, selected, ignore, passThrough }
    /// Gmail key to Mail shortcut. Key codes are US layout virtual key codes; flags are Mail's modifiers.
    static let bindings: [String: Shortcut] = [
        "j": Shortcut(name: "Next message", keyCode: 125, flags: [], repeats: true),
        "k": Shortcut(name: "Previous message", keyCode: 126, flags: [], repeats: true),
        "e": Shortcut(name: "Archive", keyCode: 0, flags: [.maskControl, .maskCommand], repeats: false),
        "r": Shortcut(name: "Reply", keyCode: 15, flags: [.maskCommand], repeats: false),
        "a": Shortcut(name: "Reply all", keyCode: 15, flags: [.maskCommand, .maskShift], repeats: false),
        "f": Shortcut(name: "Forward", keyCode: 3, flags: [.maskCommand, .maskShift], repeats: false),
        "c": Shortcut(name: "Compose", keyCode: 45, flags: [.maskCommand], repeats: false),
        "/": Shortcut(name: "Search", keyCode: 3, flags: [.maskCommand, .maskAlternate], repeats: false),
    ]

    /// The shortcut for a typed character, or nil if it isn't one or any modifier is held.
    static func shortcut(character: String, flags: CGEventFlags) -> Shortcut? {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
        guard flags.intersection(modifiers).isEmpty else { return nil }
        return bindings[character.lowercased()]
    }

    // Unknown focus, editors, and dialogs always retain ordinary typing.
    static func isBrowsing(windowID: String?, hasSheet: Bool, ancestry: [(role: String, id: String?)]) -> Bool {
        guard let windowID, windowID.hasPrefix("Mail.messageViewer.window."), !hasSheet, !ancestry.isEmpty else { return false }
        let protectedRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXSheet", "AXDialog"]
        return !ancestry.contains { protectedRoles.contains($0.role) }
    }

    /// True when the user is browsing and the message list itself has focus.
    static func allows(windowID: String?, hasSheet: Bool, ancestry: [(role: String, id: String?)]) -> Bool {
        isBrowsing(windowID: windowID, hasSheet: hasSheet, ancestry: ancestry)
            && ancestry.contains { $0.role == "AXTable" && $0.id == "Mail.messageList" }
    }

    /// Decides what E archives, given whether the user is browsing, list focus and the hover location.
    static func archiveTarget(isBrowsing: Bool, listFocused: Bool, hover: HoverLocation) -> ArchiveTarget {
        guard isBrowsing else { return .passThrough }
        switch hover {
        case .message: return .hovered
        case .listGap: return .ignore
        case .elsewhere: return listFocused ? .selected : .passThrough
        }
    }

    /// After an archive, Gmail moves to the message that was below. Once Mail has removed
    /// the row, that message sits at the archived row's index. Returns nil while Mail has
    /// not removed it yet, or when the archived message was last (Mail's choice stands).
    static func indexAfterArchive(archivedIndex: Int, rowsBefore: Int, rowsNow: Int) -> Int? {
        guard rowsNow < rowsBefore, archivedIndex >= 0, archivedIndex < rowsNow else { return nil }
        return archivedIndex
    }
}
