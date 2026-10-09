// Tests for the shortcut rules, the focus cache, the J/K glide and the usage stats.
// A tiny runner with no dependencies: ./build.sh compiles and runs it before every build.

import Foundation
import CoreGraphics

@main struct PolicyTests {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            precondition(condition, name)
            count += 1
        }
        let table = (role: "AXTable", id: Optional("Mail.messageList"))
        let window = "Mail.messageViewer.window.1"
        check(ShortcutPolicy.allows(windowID: window, hasSheet: false, ancestry: [table]), "Message list allowed")
        check(ShortcutPolicy.allows(windowID: window, hasSheet: false, ancestry: [("AXRow", nil), table]), "Message row allowed")
        for role in ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"] {
            check(!ShortcutPolicy.allows(windowID: window, hasSheet: false, ancestry: [(role, nil), table]), "Typing protected: \(role)")
        }
        for id in [nil, "Mail.compose", "preferences"] {
            check(!ShortcutPolicy.allows(windowID: id, hasSheet: false, ancestry: [table]), "Non-viewer protected")
        }
        check(!ShortcutPolicy.allows(windowID: window, hasSheet: true, ancestry: [table]), "Sheets protected")
        check(!ShortcutPolicy.allows(windowID: window, hasSheet: false, ancestry: [("AXWebArea", nil)]), "Message body protected")
        check(!ShortcutPolicy.allows(windowID: window, hasSheet: false, ancestry: [("AXOutline", "MailboxesOutlineView")]), "Sidebar protected")
        check(!ShortcutPolicy.allows(windowID: window, hasSheet: false, ancestry: []), "Unknown focus protected")
        for flag: CGEventFlags in [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn] {
            check(ShortcutPolicy.shortcut(character: "e", flags: flag) == nil, "Existing modifier shortcuts preserved")
        }
        check(ShortcutPolicy.shortcut(character: "E", flags: [.maskAlphaShift])?.name == "Archive", "Caps lock supported")
        check(ShortcutPolicy.shortcut(character: "z", flags: []) == nil, "Other keys unchanged")
        check(ShortcutPolicy.bindings.count == 8, "Expected scope")
        check(ShortcutPolicy.bindings["e"]?.keyCode == 0 && ShortcutPolicy.bindings["e"]?.flags == [.maskCommand, .maskControl], "Archive chord")
        check(ShortcutPolicy.bindings["j"]!.repeats && !ShortcutPolicy.bindings["c"]!.repeats, "Only navigation repeats")
        check(ShortcutPolicy.archiveTarget(isBrowsing: true, listFocused: true, hover: .message) == .hovered, "Hovered message overrides selection")
        check(ShortcutPolicy.archiveTarget(isBrowsing: true, listFocused: false, hover: .message) == .hovered, "Hover does not require clicking the message list")
        check(ShortcutPolicy.archiveTarget(isBrowsing: true, listFocused: true, hover: .listGap) == .ignore, "An empty list area cannot archive an unrelated selection")
        check(ShortcutPolicy.archiveTarget(isBrowsing: true, listFocused: true, hover: .elsewhere) == .selected, "Ordinary selected-message shortcut preserved away from list")
        check(ShortcutPolicy.archiveTarget(isBrowsing: true, listFocused: false, hover: .elsewhere) == .passThrough, "Hover outside list without list focus does nothing")
        for location: ShortcutPolicy.HoverLocation in [.message, .listGap, .elsewhere] {
            check(ShortcutPolicy.archiveTarget(isBrowsing: false, listFocused: false, hover: location) == .passThrough, "Typing always protected, even while hovering")
        }
        check(ShortcutPolicy.isBrowsing(windowID: window, hasSheet: false, ancestry: [("AXOutline", "MailboxesOutlineView")]), "Sidebar focus allows hover archive")
        check(ShortcutPolicy.isBrowsing(windowID: window, hasSheet: false, ancestry: [("AXWebArea", nil)]), "Read-only message body allows hover archive")
        check(!ShortcutPolicy.isBrowsing(windowID: window, hasSheet: false, ancestry: [("AXTextField", nil), ("AXWebArea", nil)]), "Text fields inside message HTML stay protected")
        check(!ShortcutPolicy.allows(windowID: window, hasSheet: false, ancestry: [table, ("AXSheet", nil)]), "Nested sheets stay protected")
        var cache = FocusSnapshotCache<Int, Bool>()
        check(cache.value(window: 1, focus: 2) == nil, "Focus must be validated before caching")
        cache.store(true, window: 1, focus: 2)
        check(cache.value(window: 1, focus: 2) == true, "Unchanged freshly-queried focus uses fast path")
        check(cache.value(window: 1, focus: 3) == nil, "Switching to a search field cannot reuse list validation")
        check(cache.value(window: 2, focus: 2) == nil, "Switching to compose window cannot reuse list validation")
        cache.invalidate()
        check(cache.value(window: 1, focus: 2) == nil, "Focus/window notifications invalidate cached validation")
        var repeating = NavigationRepeatState()
        check(!repeating.canRepeat(keyIsDown: true, mailIsActive: true, listIsFocused: true, hasModifiers: false), "No repeat without initial navigation press")
        repeating.begin(38)
        check(repeating.canRepeat(keyIsDown: true, mailIsActive: true, listIsFocused: true, hasModifiers: false), "Held j can repeat in list")
        check(!repeating.canRepeat(keyIsDown: false, mailIsActive: true, listIsFocused: true, hasModifiers: false), "Physical key release stops even if key-up was missed")
        check(!repeating.canRepeat(keyIsDown: true, mailIsActive: false, listIsFocused: true, hasModifiers: false), "App switching stops repeat")
        check(!repeating.canRepeat(keyIsDown: true, mailIsActive: true, listIsFocused: false, hasModifiers: false), "Moving focus to an editor stops repeat")
        check(!repeating.canRepeat(keyIsDown: true, mailIsActive: true, listIsFocused: true, hasModifiers: true), "Modifier chords stop repeat")
        repeating.begin(40)
        repeating.release(38)
        check(repeating.key == 40, "Latest direction wins; releasing old direction does not stop new one")
        repeating.release(40)
        check(repeating.key == nil, "Releasing current key stops repeat")
        repeating.begin(38)
        repeating.stop()
        check(repeating.key == nil, "Pause, mouse clicks and timeout can stop repeat")
        check(NavigationRepeatState.initialDelay == 0.18 && NavigationRepeatState.interval >= 1.0 / 30.0, "Fast repeat is bounded to thirty per second")
        check(ShortcutPolicy.indexAfterArchive(archivedIndex: 3, rowsBefore: 10, rowsNow: 9) == 3, "Archive moves to the next (older) message")
        check(ShortcutPolicy.indexAfterArchive(archivedIndex: 0, rowsBefore: 10, rowsNow: 9) == 0, "Archiving the top message selects the new top")
        check(ShortcutPolicy.indexAfterArchive(archivedIndex: 3, rowsBefore: 10, rowsNow: 10) == nil, "Waits until Mail removes the row")
        check(ShortcutPolicy.indexAfterArchive(archivedIndex: 9, rowsBefore: 10, rowsNow: 9) == nil, "Archiving the last message keeps Mail's choice")
        check(ShortcutPolicy.indexAfterArchive(archivedIndex: 0, rowsBefore: 1, rowsNow: 0) == nil, "Empty mailbox selects nothing")
        var usage = UsageStats()
        check(usage.totalUses == 0 && usage.secondsSaved == 0 && usage.mostUsed == nil, "Stats start empty")
        usage.record("j"); usage.record("J"); usage.record("e"); usage.record("x")
        check(usage.counts == ["j": 2, "e": 1], "Stats count shortcuts case-insensitively and ignore other keys")
        check(usage.totalUses == 3, "Total uses add up")
        check(usage.secondsSaved == 4, "Time saved rounds to the nearest second (2 x 1.42 + 1.62 = 4.46)")
        check(usage.mostUsed?.key == "j" && usage.mostUsed?.count == 2, "Most used shortcut wins")
        check(UsageStats(counts: ["a": 1, "c": 1]).mostUsed?.key == "a", "Ties resolve alphabetically")
        check(UsageStats(counts: ["k": 1]).secondsSaved == 1, "1.42 s rounds down to 1 s")
        check(UsageStats(counts: ["e": 1]).secondsSaved == 2, "1.62 s rounds up to 2 s")
        check(UsageStats(counts: ["q": 5, "j": -1]).totalUses == 0, "Stored junk is dropped")
        check(UsageStats.format(seconds: 0) == "0s" && UsageStats.format(seconds: 59) == "59s", "Seconds format")
        check(UsageStats.format(seconds: 61) == "1m 1s" && UsageStats.format(seconds: 3723) == "1h 2m 3s", "Minutes and hours format")
        print("Passed \(count) shortcut and typing-protection checks")
    }
}
