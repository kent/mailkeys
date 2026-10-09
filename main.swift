// MailKeys: Gmail keyboard shortcuts for Apple Mail.
//
// This file is the app itself: the menu bar item, a keyboard event tap that only
// sees events headed to Mail, and the accessibility checks that decide when a
// shortcut is allowed to act. The rules live in ShortcutPolicy.swift so they can
// be tested without Mail, and the settings window lives in SettingsUI.swift.

import AppKit
import ApplicationServices
import Carbon
import IOKit

/// The app delegate. Owns the menu bar item, the Mail-only event tap and the settings window.
final class MailKeys: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var mailPID: pid_t?
    private var timer: Timer?
    /// Shortcuts whose key is down, so the matching key-up is translated too.
    private var held: [Int64: Shortcut] = [:]
    /// Keys whose key-down was swallowed. Their key-up is swallowed as well.
    private var consumedKeys: Set<Int64> = []
    private var paused = UserDefaults.standard.bool(forKey: "paused")
    /// Test Mode: shortcuts are reported in the settings window instead of performed.
    private var previewOnly = true
    private var lastPreview = "No shortcut tested yet"
    private var tapFailed = false
    /// The app holding Secure Keyboard Entry, which hides keys from the tap. nil when nobody does.
    private var secureInputHolder: String?
    private var menuOpen = false
    private var settingsPanel: SettingsPanel?
    private var settingsWindow: NSWindow? { settingsPanel?.window }
    private var mailApplication: AXUIElement?
    private var mailIsFrontmost = false
    private var workspaceObserver: NSObjectProtocol?
    private var focusObserver: AXObserver?
    private var focusCache = FocusSnapshotCache<AXIdentity, MailContext>()
    private var repeatState = NavigationRepeatState()
    private var repeatTimer: Timer?
    private var repeatShortcut: Shortcut?
    private var lastMenuState: String?
    private var archiveFollowUp: Timer?
    private var usage = UsageStats(counts: UserDefaults.standard.dictionary(forKey: "usageCounts") as? [String: Int] ?? [:])
    /// "MAILKEYS" in ASCII. Marks the events MailKeys posts so its own tap lets them through.
    private let generatedEventTag: Int64 = 0x4D41494C4B455953
    private let mailID = "com.apple.mail"

    private struct AXIdentity: Equatable {
        let element: AXUIElement
        static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
    }

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        previewOnly = UserDefaults.standard.bool(forKey: "previewOnly")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "MK"
        statusItem.button?.setAccessibilityLabel("MailKeys")
        statusItem.button?.toolTip = "MailKeys: Gmail shortcuts for Apple Mail"
        mailIsFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == mailID
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            self.mailIsFrontmost = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == self.mailID
            self.focusCache.invalidate()
            self.stopNavigationRepeat()
        }
        updateMenu()
        reconcile()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.reconcile() }
        let build = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
        if !AXIsProcessTrusted() || previewOnly || UserDefaults.standard.integer(forKey: "lastSeenBuild") < build { showSettings() }
        UserDefaults.standard.set(build, forKey: "lastSeenBuild")
        // No keyboard data, message contents, or account information is recorded.
    }

    // MARK: - Reading Mail's accessibility tree

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    /// Where Mail's keyboard focus is, reduced to the two questions the shortcuts care about.
    private struct MailContext {
        let app: AXUIElement
        let window: AXUIElement
        let isBrowsing: Bool
        let listFocused: Bool
    }

    /// A message row and the table that contains it.
    private struct HoverTarget {
        let row: AXUIElement
        let table: AXUIElement
    }

    /// Reads Mail's focused window and element, then asks ShortcutPolicy whether the user is
    /// browsing (no editor, sheet or dialog in the way) and whether the message list has focus.
    /// Returns nil when Mail is not frontmost or does not answer in time; callers then let the key through.
    private func mailContext(requireFrontmost: Bool = true, useCache: Bool = true) -> MailContext? {
        guard let app = mailApplication, !requireFrontmost || mailIsFrontmost else { return nil }
        // One IPC, including on every repeat. Never trust a timer-only focus cache.
        var values: CFArray?
        let names = [kAXFocusedWindowAttribute, kAXFocusedUIElementAttribute] as CFArray
        guard AXUIElementCopyMultipleAttributeValues(app, names, .stopOnError, &values) == .success,
              let values = values as? [CFTypeRef], values.count == 2,
              let window = element(values[0]), let focus = element(values[1]) else {
            focusCache.invalidate()
            return nil
        }
        let windowIdentity = AXIdentity(element: window)
        let focusIdentity = AXIdentity(element: focus)
        if useCache, let cached = focusCache.value(window: windowIdentity, focus: focusIdentity) { return cached }
        focusCache.invalidate()
        let windowID = attribute(window, kAXIdentifierAttribute) as? String
        let children = attribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? []
        let hasSheet = children.contains { attribute($0, kAXRoleAttribute) as? String == kAXSheetRole }
        var ancestry: [(role: String, id: String?)] = []
        var node: AXUIElement? = focus
        for _ in 0..<16 {
            guard let current = node, let role = attribute(current, kAXRoleAttribute) as? String else { return nil }
            ancestry.append((role, attribute(current, kAXIdentifierAttribute) as? String))
            if role == kAXWindowRole || role == kAXApplicationRole { break }
            node = element(attribute(current, kAXParentAttribute))
        }
        let context = MailContext(app: app, window: window,
            isBrowsing: ShortcutPolicy.isBrowsing(windowID: windowID, hasSheet: hasSheet, ancestry: ancestry),
            listFocused: ShortcutPolicy.allows(windowID: windowID, hasSheet: hasSheet, ancestry: ancestry))
        // Cache only the stable message table itself, never editors or row objects.
        if context.listFocused, ancestry.first?.role == kAXTableRole, ancestry.first?.id == "Mail.messageList" {
            focusCache.store(context, window: windowIdentity, focus: focusIdentity)
        }
        return context
    }

    private func messageListIsFocused() -> Bool { mailContext()?.listFocused == true }

    // Check structural identifiers only; no message contents are read.
    private func isMessageRow(_ row: AXUIElement) -> Bool {
        var remaining = [row]
        for _ in 0..<24 {
            guard !remaining.isEmpty else { return false }
            let current = remaining.removeFirst()
            if attribute(current, kAXIdentifierAttribute) as? String == "Mail.messageList.cell.view.subjectLabel" { return true }
            let children = attribute(current, kAXChildrenAttribute) as? [AXUIElement] ?? []
            remaining.append(contentsOf: children.prefix(16))
        }
        return false
    }

    /// Hit-tests Mail at the pointer (or `testPoint`) and reports whether it is over a message row,
    /// over the list but between rows, or somewhere else entirely.
    private func hoveredMessage(in context: MailContext, at testPoint: CGPoint? = nil) -> (ShortcutPolicy.HoverLocation, HoverTarget?) {
        guard let point = testPoint ?? CGEvent(source: nil)?.location else { return (.listGap, nil) }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(context.app, Float(point.x), Float(point.y), &hit) == .success else {
            // If hit testing fails, do not fall back to a potentially unrelated selection.
            return (.listGap, nil)
        }
        var node = hit
        var row: AXUIElement?
        for _ in 0..<20 {
            guard let current = node, let role = attribute(current, kAXRoleAttribute) as? String else { break }
            if role == kAXRowRole { row = current }
            if role == kAXTableRole, attribute(current, kAXIdentifierAttribute) as? String == "Mail.messageList" {
                guard let window = element(attribute(current, kAXWindowAttribute)), CFEqual(window, context.window),
                      let row, isMessageRow(row) else { return (.listGap, nil) }
                return (.message, HoverTarget(row: row, table: current))
            }
            if role == kAXWindowRole || role == kAXApplicationRole { break }
            node = element(attribute(current, kAXParentAttribute))
        }
        return (.elsewhere, nil)
    }

    /// Makes the hovered row the only selected message, then confirms Mail agrees.
    /// Archive only proceeds when this returns true.
    private func selectOnlyHoveredMessage(_ target: HoverTarget, in context: MailContext, requireFrontmost: Bool = true) -> Bool {
        guard let current = mailContext(requireFrontmost: requireFrontmost), current.isBrowsing, CFEqual(current.window, context.window) else { return false }
        // Replacing the complete selection prevents archiving other selected messages.
        let selection = [target.row] as CFArray
        guard AXUIElementSetAttributeValue(target.table, kAXSelectedRowsAttribute as CFString, selection) == .success else { return false }
        _ = AXUIElementSetAttributeValue(target.table, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard let selected = attribute(target.table, kAXSelectedRowsAttribute) as? [AXUIElement],
              selected.count == 1, CFEqual(selected[0], target.row),
              let after = mailContext(requireFrontmost: requireFrontmost), after.listFocused, CFEqual(after.window, context.window) else { return false }
        return true
    }

    // MARK: - After an archive

    /// Mail picks its own neighbour after an archive, often the message above.
    /// Like Gmail, MailKeys then selects the message that was below the archived one.
    private func selectNextAfterArchive(table: AXUIElement, row: AXUIElement) {
        cancelArchiveFollowUp()
        var rowsBefore: CFIndex = 0
        guard let archivedIndex = attribute(row, kAXIndexAttribute) as? Int,
              AXUIElementGetAttributeValueCount(table, kAXRowsAttribute as CFString, &rowsBefore) == .success else { return }
        let deadline = Date().addingTimeInterval(1.5)
        archiveFollowUp = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self else { return }
            var rowsNow: CFIndex = 0
            guard Date() < deadline,
                  AXUIElementGetAttributeValueCount(table, kAXRowsAttribute as CFString, &rowsNow) == .success else {
                self.cancelArchiveFollowUp(); return
            }
            guard rowsNow < rowsBefore else { return }
            self.cancelArchiveFollowUp()
            guard let index = ShortcutPolicy.indexAfterArchive(archivedIndex: archivedIndex, rowsBefore: rowsBefore, rowsNow: rowsNow) else { return }
            var values: CFArray?
            guard AXUIElementCopyAttributeValues(table, kAXRowsAttribute as CFString, index, 1, &values) == .success,
                  let next = (values as? [AXUIElement])?.first, self.isMessageRow(next) else { return }
            _ = AXUIElementSetAttributeValue(table, kAXSelectedRowsAttribute as CFString, [next] as CFArray)
        }
    }

    private func cancelArchiveFollowUp() {
        archiveFollowUp?.invalidate()
        archiveFollowUp = nil
    }

    /// The single selected row of Mail's focused message list, if exactly one is selected.
    private func selectedMessage(in context: MailContext) -> HoverTarget? {
        var node = element(attribute(context.app, kAXFocusedUIElementAttribute))
        for _ in 0..<16 {
            guard let current = node else { return nil }
            if attribute(current, kAXIdentifierAttribute) as? String == "Mail.messageList" {
                guard let rows = attribute(current, kAXSelectedRowsAttribute) as? [AXUIElement], rows.count == 1 else { return nil }
                return HoverTarget(row: rows[0], table: current)
            }
            node = element(attribute(current, kAXParentAttribute))
        }
        return nil
    }

    // MARK: - Usage stats

    private func resetUsage() {
        let alert = NSAlert()
        alert.messageText = "Reset shortcut counts?"
        alert.informativeText = "Time saved and every shortcut count go back to zero. This can’t be undone."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard let window = settingsWindow else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.usage = UsageStats()
            UserDefaults.standard.removeObject(forKey: "usageCounts")
            self.lastMenuState = nil
            self.updateMenu()
        }
    }

    /// Counts a shortcut that actually acted in Mail. Runs on the main queue, off the event tap.
    private func recordUse(_ key: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.usage.record(key)
            UserDefaults.standard.set(self.usage.counts, forKey: "usageCounts")
            self.lastMenuState = nil
            self.updateMenu()
        }
    }

    /// Test Mode feedback: updates the preview line and lights the matching key in the settings window.
    private func showTestResult(_ message: String, key: String? = nil) {
        lastPreview = message
        DispatchQueue.main.async { [weak self] in
            if let key { self?.settingsPanel?.flashKey(key) }
            self?.updateMenu()
        }
    }

    // MARK: - Event tap lifecycle

    /// Runs every second. Attaches the tap when Mail is running and permission is granted,
    /// re-attaches when Mail relaunches, and detaches when paused.
    private func reconcile() {
        secureInputHolder = currentSecureInputHolder()
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: mailID).first?.processIdentifier
        guard AXIsProcessTrusted(), !paused, let pid else {
            if tap != nil { stopTap() }
            updateMenu()
            return
        }
        if mailPID != pid || tap == nil {
            stopTap()
            mailPID = pid
            mailApplication = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(mailApplication!, 0.02)
            mailIsFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            installFocusObserver(pid: pid)
            // A process-specific event tap receives only events destined for Mail.
            // No global keyboard listener is installed.
            let eventTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            let mask = eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
            tap = CGEvent.tapCreateForPid(pid: pid, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: mask,
                callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    let helper = Unmanaged<MailKeys>.fromOpaque(context).takeUnretainedValue()
                    return helper.handle(type: type, event: event)
                }, userInfo: Unmanaged.passUnretained(self).toOpaque())
            if let tap {
                source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                tapFailed = false
            } else { tapFailed = true }
        }
        updateMenu()
    }

    private func stopTap() {
        stopNavigationRepeat()
        focusCache.invalidate()
        if let focusObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(focusObserver), .commonModes) }
        focusObserver = nil
        mailApplication = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        mailPID = nil
        held.removeAll()
        consumedKeys.removeAll()
    }

    /// Who holds Secure Keyboard Entry right now. macOS records the holder's process in the
    /// console session; if it names nothing but secure input is on, the holder is unknown.
    private func currentSecureInputHolder() -> String? {
        guard IsSecureEventInputEnabled() else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOResources"))
        guard service != 0 else { return "another app" }
        defer { IOObjectRelease(service) }
        let users = IORegistryEntryCreateCFProperty(service, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]] ?? []
        for user in users {
            guard let pid = user["kCGSSessionSecureInputPID"] as? Int, pid > 0 else { continue }
            return NSRunningApplication(processIdentifier: pid_t(pid))?.localizedName ?? "another app"
        }
        return "another app"
    }

    /// Invalidates the focus cache whenever Mail's focus or windows change.
    private func installFocusObserver(pid: pid_t) {
        var observer: AXObserver?
        guard let app = mailApplication,
              AXObserverCreate(pid, { _, _, notification, pointer in
                  guard let pointer else { return }
                  let helper = Unmanaged<MailKeys>.fromOpaque(pointer).takeUnretainedValue()
                  helper.focusCache.invalidate()
                  if notification as String != kAXFocusedUIElementChangedNotification { helper.stopNavigationRepeat() }
              }, &observer) == .success, let observer else { return }
        focusObserver = observer
        for notification in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification] {
            _ = AXObserverAddNotification(observer, app, notification as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    // MARK: - J/K glide

    /// Holding J or K repeats navigation at a fixed rate, independent of the system key repeat.
    private func startNavigationRepeat(code: Int64, shortcut: Shortcut) {
        stopNavigationRepeat()
        repeatState.begin(code)
        repeatShortcut = shortcut
        let timer = Timer(fire: Date(timeIntervalSinceNow: NavigationRepeatState.initialDelay),
                          interval: NavigationRepeatState.interval, repeats: true) { [weak self] _ in self?.repeatNavigation() }
        timer.tolerance = 0.002
        repeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopNavigationRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        repeatState.stop()
        repeatShortcut = nil
    }

    private func repeatNavigation() {
        guard !paused, !previewOnly, let pid = mailPID, let code = repeatState.key, let shortcut = repeatShortcut else {
            stopNavigationRepeat(); return
        }
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
        let keyIsDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code))
        let hasModifiers = !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty
        guard repeatState.canRepeat(keyIsDown: keyIsDown, mailIsActive: mailIsFrontmost,
                                    listIsFocused: keyIsDown && mailIsFrontmost && !hasModifiers && messageListIsFocused(),
                                    hasModifiers: hasModifiers) else { stopNavigationRepeat(); return }
        // A repeating run-loop timer coalesces late ticks rather than queuing a
        // burst of navigation after Mail has been busy. Only these two keys repeat.
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: down) else { continue }
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: generatedEventTag)
            event.setIntegerValueField(.keyboardEventAutorepeat, value: down ? 1 : 0)
            event.postToPid(pid)
        }
    }

    // MARK: - Key handling

    /// Rewrites the Gmail key into the Mail shortcut it stands for, in place.
    private func translated(_ event: CGEvent, _ shortcut: Shortcut) -> Unmanaged<CGEvent> {
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(shortcut.keyCode))
        event.flags = shortcut.flags
        // Drop any cached Unicode text from the original letter.
        event.keyboardSetUnicodeString(stringLength: 0, unicodeString: nil)
        return Unmanaged.passUnretained(event)
    }

    /// The event tap callback. Returns the event (possibly translated) to let it reach Mail,
    /// or nil to swallow it. Anything MailKeys is unsure about passes through untouched.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == generatedEventTag { return Unmanaged.passUnretained(event) }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stopNavigationRepeat()
            focusCache.invalidate()
            held.removeAll()
            consumedKeys.removeAll()
            if let tap, !paused { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown { cancelArchiveFollowUp() }
        if type == .flagsChanged || type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            stopNavigationRepeat()
            focusCache.invalidate()
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            if repeatState.release(code) { stopNavigationRepeat() }
            if consumedKeys.remove(code) != nil { return nil }
            guard let shortcut = held.removeValue(forKey: code) else { return Unmanaged.passUnretained(event) }
            return previewOnly ? nil : translated(event, shortcut)
        }
        guard type == .keyDown, !paused else { return Unmanaged.passUnretained(event) }
        if consumedKeys.contains(code) { return nil }
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            guard held[code] != nil else { return Unmanaged.passUnretained(event) }
            // Navigation uses its own fast, Mail-only repeat timer. Consuming
            // native repeats prevents doubling and prevents accent popovers.
            return nil
        }
        stopNavigationRepeat()
        cancelArchiveFollowUp()
        var characters = [UniChar](repeating: 0, count: 8)
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: characters.count, actualStringLength: &length, unicodeString: &characters)
        let character = String(utf16CodeUnits: characters, count: min(length, characters.count))
        guard let shortcut = ShortcutPolicy.shortcut(character: character, flags: event.flags),
              let context = mailContext() else { return Unmanaged.passUnretained(event) }
        if character.lowercased() == "e", context.isBrowsing {
            let (location, target) = hoveredMessage(in: context)
            switch ShortcutPolicy.archiveTarget(isBrowsing: context.isBrowsing, listFocused: context.listFocused, hover: location) {
            case .hovered:
                guard let target else { consumedKeys.insert(code); return nil }
                if previewOnly {
                    consumedKeys.insert(code)
                    showTestResult("Test: e → Archive hovered message", key: "e")
                    return nil
                }
                guard selectOnlyHoveredMessage(target, in: context) else {
                    consumedKeys.insert(code)
                    NSSound.beep()
                    return nil
                }
                held[code] = shortcut
                selectNextAfterArchive(table: target.table, row: target.row)
                recordUse("e")
                return translated(event, shortcut)
            case .ignore:
                consumedKeys.insert(code)
                if previewOnly { showTestResult("Test: no message under pointer; nothing archived") }
                return nil
            case .passThrough: return Unmanaged.passUnretained(event)
            case .selected: break
            }
        }
        guard context.listFocused else { return Unmanaged.passUnretained(event) }
        held[code] = shortcut
        if previewOnly {
            showTestResult("Test: \(character) → \(shortcut.name)", key: character)
            return nil
        }
        if shortcut.repeats { startNavigationRepeat(code: code, shortcut: shortcut) }
        else { focusCache.invalidate() }
        if character.lowercased() == "e", let target = selectedMessage(in: context) {
            selectNextAfterArchive(table: target.table, row: target.row)
        }
        recordUse(character)
        return translated(event, shortcut)
    }

    // MARK: - Menu bar

    private func item(_ title: String, action: Selector? = nil, checked: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = checked ? .on : .off
        return item
    }

    private func updateMenu() {
        guard statusItem != nil else { return }
        let state: String
        let tone: StatusPill.Tone
        let trusted = AXIsProcessTrusted()
        if !trusted { state = "Needs Accessibility permission"; tone = .attention }
        else if paused { state = "Paused"; tone = .paused }
        else if let blocked = SecureInput.status(holder: secureInputHolder) { state = blocked; tone = .attention }
        else if tapFailed { state = "Could not attach to Mail"; tone = .attention }
        else if tap == nil { state = "Waiting for Apple Mail"; tone = .waiting }
        else { state = "Ready: hover a message and press e"; tone = .ready }
        settingsPanel?.update(status: state, tone: tone, trusted: trusted, paused: paused,
                              testMode: previewOnly, preview: lastPreview, blockedBy: secureInputHolder)
        settingsPanel?.updateUsage(usage)
        guard !menuOpen else { return }
        let saved = usage.totalUses == 0 ? "No time saved yet"
            : "Saved \(UsageStats.format(seconds: usage.secondsSaved)) across \(usage.totalUses) shortcuts"
        let menuState = "\(state)|\(paused)|\(previewOnly)|\(lastPreview)|\(saved)|\(secureInputHolder ?? "")"
        guard menuState != lastMenuState else { return }
        lastMenuState = menuState
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item("MailKeys · \(state)"))
        if let holder = secureInputHolder { menu.addItem(item(SecureInput.menuHint(holder: holder))) }
        menu.addItem(item(saved))
        menu.addItem(.separator())
        menu.addItem(item("Pause Shortcuts", action: #selector(togglePause), checked: paused))
        menu.addItem(item("Show Shortcuts…", action: #selector(showShortcuts)))
        menu.addItem(item("Settings…", action: #selector(showSettings)))
        menu.addItem(item("Open Accessibility Settings…", action: #selector(openPermissions)))
        menu.addItem(.separator())
        menu.addItem(item("Test Mode (no actions)", action: #selector(togglePreview), checked: previewOnly))
        if previewOnly { menu.addItem(item(lastPreview)) }
        menu.addItem(.separator())
        menu.addItem(item("Quit MailKeys", action: #selector(quit)))
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    // MARK: - Actions

    @objc private func togglePause() {
        paused.toggle()
        UserDefaults.standard.set(paused, forKey: "paused")
        reconcile()
    }
    @objc private func togglePreview() {
        stopNavigationRepeat()
        previewOnly.toggle()
        UserDefaults.standard.set(previewOnly, forKey: "previewOnly")
        held.removeAll()
        consumedKeys.removeAll()
        updateMenu()
    }
    @objc private func showShortcuts() {
        let alert = NSAlert()
        alert.messageText = "Gmail shortcuts in Apple Mail"
        alert.informativeText = "j / k    Next / previous message\ne         Archive the hovered message\nr         Reply\na         Reply all\nf          Forward\nc         Compose\n/          Search\n\nWith Mail active, hover over a message and press e to archive it. No click needed. Away from the list, e uses the selected message when the list has focus. Other shortcuts require focus in the message list. Typing in search, compose windows, dialogs, and other apps is protected.\n\nMailKeys does not record keystrokes or read message contents."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    @objc private func openPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: - Diagnostics

    /// Exercises the real hover path against Mail's already-selected message.
    /// No message is archived and the selection stays the same.
    @objc private func checkHoverSupport() {
        // This window must not cover the point being hit-tested in Mail.
        let wasVisible = settingsWindow?.isVisible == true
        settingsWindow?.orderOut(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.runHoverSupportCheck()
            if wasVisible { self.settingsWindow?.orderFront(nil) }
        }
    }

    private func runHoverSupportCheck() {
        guard let context = mailContext(requireFrontmost: false), context.listFocused,
              let focus = element(attribute(context.app, kAXFocusedUIElementAttribute)) else {
            settingsPanel?.setHoverResult("Select one message in Mail, then check again.", ok: false)
            return
        }
        var node: AXUIElement? = focus
        var table: AXUIElement?
        for _ in 0..<16 {
            guard let current = node else { break }
            if attribute(current, kAXIdentifierAttribute) as? String == "Mail.messageList" { table = current; break }
            node = element(attribute(current, kAXParentAttribute))
        }
        guard let table, let selected = attribute(table, kAXSelectedRowsAttribute) as? [AXUIElement], selected.count == 1,
              let positionValue = attribute(selected[0], kAXPositionAttribute),
              let sizeValue = attribute(selected[0], kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            settingsPanel?.setHoverResult("Select one visible message in Mail, then check again.", ok: false)
            return
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size), size.width > 0, size.height > 0 else {
            settingsPanel?.setHoverResult("Mail did not expose the message’s position.", ok: false)
            return
        }
        let point = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        let (location, target) = hoveredMessage(in: context, at: point)
        guard location == .message, let target, CFEqual(target.row, selected[0]) else {
            settingsPanel?.setHoverResult("Hover targeting could not identify the selected message.", ok: false)
            return
        }
        guard selectOnlyHoveredMessage(target, in: context, requireFrontmost: false) else {
            settingsPanel?.setHoverResult("Mail did not confirm a single-message selection.", ok: false)
            return
        }
        settingsPanel?.setHoverResult("Verified. Hover archive works here.", ok: true)
    }

    /// Times the focus check that runs on every key press, with and without the cache.
    @objc private func checkResponsiveness() {
        guard mailContext(requireFrontmost: false)?.listFocused == true else {
            settingsPanel?.setSpeedResult("Click the message list in Mail, then check again.", ok: false)
            return
        }
        func measure(cached: Bool) -> [Double] {
            (0..<30).compactMap { _ in
                let start = DispatchTime.now().uptimeNanoseconds
                guard mailContext(requireFrontmost: false, useCache: cached)?.listFocused == true else { return nil }
                return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            }.sorted()
        }
        let uncached = measure(cached: false)
        _ = mailContext(requireFrontmost: false)
        let cached = measure(cached: true)
        guard uncached.count == 30, cached.count == 30 else {
            settingsPanel?.setSpeedResult("Mail’s focus changed during the check. Try again.", ok: false)
            return
        }
        settingsPanel?.setSpeedResult(String(format: "Instant. About %.1f ms per key.", cached[15]), ok: true,
            detail: String(format: "%.2f ms median, %.2f ms p95, %.2f ms uncached. Holding J or K moves 30 messages a second.", cached[15], cached[28], uncached[15]))
    }
    // MARK: - Settings window

    @objc private func showSettings() {
        if settingsPanel == nil {
            settingsPanel = SettingsPanel(actions: .init(
                quit: { NSApp.terminate(nil) },
                grantAccess: { [weak self] in self?.openPermissions() },
                togglePause: { [weak self] in self?.togglePause() },
                toggleTestMode: { [weak self] in self?.togglePreview() },
                checkHover: { [weak self] in self?.checkHoverSupport() },
                checkSpeed: { [weak self] in self?.checkResponsiveness() },
                resetUsage: { [weak self] in self?.resetUsage() }))
            settingsPanel?.window.center()
            lastMenuState = nil
        }
        updateMenu()
        settingsPanel?.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        stopTap(); timer?.invalidate()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
    }
}

// MARK: - Entry point

let application = NSApplication.shared
// Development helpers: render the app icon or the settings window to PNGs, then exit.
if let path = ProcessInfo.processInfo.environment["MAILKEYS_ICON"] {
    SettingsPanel.renderIcon(to: path)
    exit(0)
}
if let directory = ProcessInfo.processInfo.environment["MAILKEYS_SNAPSHOT"] {
    SettingsPanel.renderSnapshots(to: directory)
    exit(0)
}
let delegate = MailKeys()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
