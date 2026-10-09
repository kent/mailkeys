// The settings window and the app icon, drawn entirely in code.
//
// Every visual here is a small custom NSView, so the window needs no asset
// catalogue and renders identically offscreen. That is what makes the
// MAILKEYS_SNAPSHOT and MAILKEYS_ICON development helpers possible.

import AppKit
import ServiceManagement

// MARK: - Palette

/// Colours and helpers. Dynamic colours resolve per appearance, so light and dark mode share one palette.
enum Palette {
    static func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }
    static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }
    static let pane = dynamic(hex(0xF3F3F7), hex(0x1A1A1F))
    static let card = dynamic(.white, hex(0x25252C))
    static let cardBorder = dynamic(hex(0x000000, 0.055), hex(0xFFFFFF, 0.075))
    static let hairline = dynamic(hex(0x000000, 0.07), hex(0xFFFFFF, 0.07))
    static let well = dynamic(hex(0x000000, 0.04), hex(0x000000, 0.22))
    static let violet = hex(0x6B45F5)
    static let count = dynamic(hex(0x6B45F5), hex(0xB49CFF))
    static let ink = dynamic(hex(0x1D1D24), hex(0xF4F4F7))
    static let subtle = dynamic(hex(0x6E6E7A), hex(0x9C9CA8))
}

/// The system font in its rounded design, falling back to the default design.
func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

/// A non-selectable label. Pass `wrapWidth` for text that may wrap onto more lines.
func makeLabel(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = Palette.ink,
               rounded: Bool = false, wrapWidth: CGFloat? = nil, alignment: NSTextAlignment = .left) -> NSTextField {
    let field = wrapWidth == nil ? NSTextField(labelWithString: string) : NSTextField(wrappingLabelWithString: string)
    field.font = rounded ? roundedFont(size, weight) : .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.alignment = alignment
    field.isSelectable = false
    if let wrapWidth { field.preferredMaxLayoutWidth = wrapWidth }
    return field
}

private extension NSView {
    var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

/// A soft radial glow, used for the light blooms in the sidebar and icon.
private func blob(at center: NSPoint, radius: CGFloat, color: NSColor) {
    NSGradient(colors: [color, color.withAlphaComponent(0)])?
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

// MARK: - Keycap

/// A physical-looking key with depth. Lights up when its shortcut fires in Test Mode.
final class KeycapView: NSView {
    var glyph: String { didSet { needsDisplay = true; setAccessibilityLabel("\(glyph.uppercased()) key") } }
    private let keySize: CGFloat
    private var pressed = false { didSet { needsDisplay = true } }
    /// Lit keys draw violet. Setting it is immediate; flash() lights the key and fades it out.
    var lit = false { didSet { litAmount = lit ? 1 : 0 } }
    private var litAmount: CGFloat = 0 { didSet { needsDisplay = true } }
    private var fadeTimer: Timer?
    private static let padding: CGFloat = 4

    init(_ glyph: String, size: CGFloat = 38) {
        self.glyph = glyph
        keySize = size
        super.init(frame: NSRect(x: 0, y: 0, width: size + Self.padding * 2, height: size + Self.padding * 2))
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(glyph.uppercased()) key")
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: keySize + Self.padding * 2, height: keySize + Self.padding * 2) }

    func flash() {
        fadeTimer?.invalidate()
        litAmount = 1
        let began = CACurrentMediaTime() + 0.2
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = (CACurrentMediaTime() - began) / 0.25
            guard progress > 0 else { return }
            self.litAmount = max(0, 1 - CGFloat(progress))
            if progress >= 1 { timer.invalidate() }
        }
    }

    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) { pressed = false }

    override func draw(_ dirtyRect: NSRect) {
        drawKey(lit: false, down: pressed || litAmount > 0.5)
        guard litAmount > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setAlpha(litAmount)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        drawKey(lit: true, down: pressed || litAmount > 0.5)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private func drawKey(lit: Bool, down: Bool) {
        let dark = isDark
        let key = bounds.insetBy(dx: Self.padding, dy: Self.padding)
        let radius = keySize * 0.24

        // Body: the darker skirt that shows the key's depth.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(down ? 0 : (dark ? 0.55 : 0.2))
        shadow.shadowOffset = NSSize(width: 0, height: -1.5)
        shadow.shadowBlurRadius = 3
        shadow.set()
        let skirt: NSColor = lit ? Palette.hex(0x5532E0) : (dark ? Palette.hex(0x141418) : Palette.hex(0xC3C5CF))
        skirt.setFill()
        NSBezierPath(roundedRect: key, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()

        // Face: sits higher on the skirt until pressed.
        let depth: CGFloat = down ? 1 : 3.5
        var face = key.insetBy(dx: 1, dy: 0)
        face.origin.y += depth
        face.size.height -= depth + 1
        let faceRadius = radius - 1
        let facePath = NSBezierPath(roundedRect: face, xRadius: faceRadius, yRadius: faceRadius)
        let gradient: NSGradient?
        if lit { gradient = NSGradient(starting: Palette.hex(0x9479FF), ending: Palette.hex(0x6B45F5)) }
        else if dark { gradient = NSGradient(starting: Palette.hex(0x5E5F6A), ending: Palette.hex(0x41424B)) }
        else { gradient = NSGradient(starting: .white, ending: Palette.hex(0xECEDF3)) }
        gradient?.draw(in: facePath, angle: -90)

        // A soft inner highlight gives the face its glossy bevel.
        NSGraphicsContext.saveGraphicsState()
        facePath.addClip()
        let sheen = NSRect(x: face.minX, y: face.maxY - face.height * 0.45, width: face.width, height: face.height * 0.45)
        NSGradient(colors: [NSColor.white.withAlphaComponent(lit ? 0.22 : (dark ? 0.1 : 0.7)), NSColor.white.withAlphaComponent(0)])?
            .draw(in: sheen, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        let color: NSColor = lit ? .white : (dark ? Palette.hex(0xF2F2F6) : Palette.hex(0x2A2B33))
        let attributes: [NSAttributedString.Key: Any] = [.font: roundedFont(keySize * 0.4, .semibold), .foregroundColor: color]
        let text = NSAttributedString(string: glyph.uppercased(), attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(x: face.midX - size.width / 2, y: face.midY - size.height / 2 + 0.5))
    }
}

// MARK: - Icon tile

/// A rounded, glossy square holding an SF Symbol, like a tiny app icon.
final class IconTile: NSView {
    private var symbol: String
    private var colors: [NSColor]
    private let side: CGFloat

    init(symbol: String, colors: [NSColor], side: CGFloat = 34) {
        self.symbol = symbol
        self.colors = colors
        self.side = side
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: side + 4, height: side + 4) }

    func update(symbol: String, colors: [NSColor]) {
        self.symbol = symbol
        self.colors = colors
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let tile = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: tile, xRadius: side * 0.28, yRadius: side * 0.28)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = colors.last?.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2
        shadow.set()
        NSGradient(colors: colors)?.draw(in: path, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.3), NSColor.white.withAlphaComponent(0)])?
            .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        let config = NSImage.SymbolConfiguration(pointSize: side * 0.46, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let size = image.size
        image.draw(in: NSRect(x: tile.midX - size.width / 2, y: tile.midY - size.height / 2, width: size.width, height: size.height))
    }
}

// MARK: - Buttons

/// A capsule button. `.solid` and `.glass` sit on the sidebar gradient; `.secondary` and `.tinted` sit on cards.
final class PillButton: NSButton {
    enum Style { case solid, glass, tinted(NSColor), secondary }
    var style: Style { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    private let handler: () -> Void
    private var hovering = false { didSet { needsDisplay = true } }

    init(_ title: String, style: Style, handler: @escaping () -> Void) {
        self.style = style
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        target = self
        action = #selector(fire)
        setButtonType(.momentaryPushIn)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }

    private var isLarge: Bool { switch style { case .solid, .glass: return true; default: return false } }
    private var titleFont: NSFont { roundedFont(isLarge ? 14 : 12.5, isLarge ? .medium : .semibold) }

    override var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    override var intrinsicContentSize: NSSize {
        let width = (title as NSString).size(withAttributes: [.font: titleFont]).width
        return isLarge ? NSSize(width: ceil(width) + 44, height: 40) : NSSize(width: max(96, ceil(width) + 28), height: 30)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func draw(_ dirtyRect: NSRect) {
        let down = isHighlighted
        let rect = bounds.insetBy(dx: 2, dy: 3).offsetBy(dx: 0, dy: down ? -0.5 : 0)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        let textColor: NSColor
        switch style {
        case .solid:
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = Palette.hex(0x2A0E7A, down ? 0.25 : 0.4)
            shadow.shadowOffset = NSSize(width: 0, height: down ? -1 : -2)
            shadow.shadowBlurRadius = down ? 2 : 5
            shadow.set()
            NSGradient(starting: .white, ending: Palette.hex(hovering ? 0xF1EDFF : 0xEAE6FA))?.draw(in: path, angle: -90)
            NSGraphicsContext.restoreGraphicsState()
            textColor = Palette.hex(0x5531E0)
        case .glass:
            NSColor.white.withAlphaComponent(down ? 0.12 : (hovering ? 0.26 : 0.18)).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.35).setStroke()
            let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: rect.height / 2, yRadius: rect.height / 2)
            rim.lineWidth = 1
            rim.stroke()
            textColor = .white
        case .secondary:
            let base: CGFloat = isDark ? 0.1 : 0.055
            (isDark ? NSColor.white : NSColor.black).withAlphaComponent(base + (down ? 0.08 : (hovering ? 0.04 : 0))).setFill()
            path.fill()
            textColor = Palette.ink
        case .tinted(let tint):
            let base: CGFloat = isDark ? 0.22 : 0.12
            tint.withAlphaComponent(base + (down ? 0.12 : (hovering ? 0.06 : 0))).setFill()
            path.fill()
            textColor = isDark ? tint.blended(withFraction: 0.45, of: .white) ?? tint : tint
        }
        if case .solid = style {
            // Glossy cap on the upper half.
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            NSGradient(colors: [NSColor.white.withAlphaComponent(0.9), NSColor.white.withAlphaComponent(0)])?
                .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
            NSGraphicsContext.restoreGraphicsState()
        }
        let text = NSAttributedString(string: title, attributes: [.font: titleFont, .foregroundColor: textColor])
        let size = text.size()
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }
}

// MARK: - Hero

/// The gradient sidebar background, with its own darker gradient in dark mode.
final class HeroView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = isDark
        // Dark mode gets its own deeper indigo-to-plum gradient rather than a dimmed light one.
        let colors = dark ? [Palette.hex(0x2C3896), Palette.hex(0x45289A), Palette.hex(0x7A2566)]
                          : [Palette.hex(0x4D6BFF), Palette.hex(0x7A3EF0), Palette.hex(0xD6409C)]
        NSGradient(colors: colors, atLocations: [0, 0.55, 1], colorSpace: .sRGB)?.draw(in: bounds, angle: -65)
        let glow: CGFloat = dark ? 0.45 : 1
        blob(at: NSPoint(x: bounds.minX + 10, y: bounds.maxY - 40), radius: 220, color: Palette.hex(0x45D8FF, 0.55 * glow))
        blob(at: NSPoint(x: bounds.maxX + 20, y: bounds.minY + 60), radius: 230, color: Palette.hex(0xFF9B57, 0.5 * glow))
        blob(at: NSPoint(x: bounds.midX, y: bounds.maxY - 170), radius: 150, color: NSColor.white.withAlphaComponent(0.16 * glow))
        // Faint floating keycaps add depth behind the content.
        for (x, y, side, angle) in [(-0.06, 0.6, 84.0, -14.0), (-0.07, 0.3, 70.0, 10.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: bounds.width * x, yBy: bounds.height * y)
            transform.rotate(byDegrees: angle)
            transform.concat()
            let rect = NSRect(x: -side / 2, y: -side / 2, width: side, height: side)
            let key = NSBezierPath(roundedRect: rect, xRadius: side * 0.24, yRadius: side * 0.24)
            NSGradient(colors: [NSColor.white.withAlphaComponent(0.1), NSColor.white.withAlphaComponent(0.02)])?.draw(in: key, angle: -90)
            NSColor.white.withAlphaComponent(0.12).setStroke()
            key.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor.black.withAlphaComponent(0.12).setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
    }
}

/// A frosted panel for content on the sidebar gradient.
final class GlassPanel: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.2), NSColor.white.withAlphaComponent(0.08)])?.draw(in: path, angle: -90)
        NSColor.white.withAlphaComponent(0.28).setStroke()
        path.stroke()
    }
}

/// The real app icon, drawn from the same code as AppIcon.icns.
final class AppIconView: NSView {
    private static let side: CGFloat = 112
    // Rasterized once at full size: NSShadow does not scale with the context, so drawing
    // the icon live at 128 pt would blow its shadows out past the image bounds.
    private static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        if let rep = SettingsPanel.iconRep(pixels: 512) { image.addRepresentation(rep) }
        return image
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.side, height: Self.side) }

    override func draw(_ dirtyRect: NSRect) {
        Self.image.draw(in: bounds)
        // A light rim separates the gradient icon from the gradient sidebar.
        let scale = bounds.width / 1024
        let tile = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale).insetBy(dx: 0.5, dy: 0.5)
        let rim = NSBezierPath(roundedRect: tile, xRadius: 186 * scale, yRadius: 186 * scale)
        NSColor.white.withAlphaComponent(0.3).setStroke()
        rim.stroke()
    }
}

/// Shows MailKeys' state with a coloured dot: ready, waiting, paused, test mode or needs attention.
final class StatusPill: NSView {
    enum Tone { case ready, waiting, attention, paused, testing
        var color: NSColor {
            switch self {
            case .ready: return Palette.hex(0x48F59A)
            case .waiting: return Palette.hex(0x8FD8FF)
            case .attention: return Palette.hex(0xFF6B6B)
            case .paused: return Palette.hex(0xFFC24D)
            case .testing: return Palette.hex(0xB794FF)
            }
        }
    }
    private let label = makeLabel("", size: 12, weight: .medium, color: .white, rounded: true)
    private static func short(_ text: String, tone: Tone) -> String {
        switch tone {
        case .ready: return "Ready in Mail"
        case .paused: return "Paused"
        case .attention: return text.hasPrefix("Needs") ? "Needs permission" : "Can’t reach Mail"
        case .waiting: return "Waiting for Mail"
        case .testing: return "Test Mode on"
        }
    }
    var tone: Tone = .waiting { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 28),
            widthAnchor.constraint(equalToConstant: 150),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ text: String, tone: Tone) {
        label.stringValue = Self.short(text, tone: tone)
        needsDisplay = true
        self.tone = tone
        setAccessibilityLabel("Status: \(text)")
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.black.withAlphaComponent(0.16).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        path.stroke()
        let dot = NSRect(x: label.frame.minX - 15, y: bounds.midY - 4, width: 8, height: 8)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = tone.color
        glow.shadowBlurRadius = 6
        glow.set()
        tone.color.setFill()
        NSBezierPath(ovalIn: dot).fill()
        NSGraphicsContext.restoreGraphicsState()
        if tone == .testing {
            let ring = NSBezierPath(ovalIn: dot.insetBy(dx: -0.5, dy: -0.5))
            ring.lineWidth = 1.5
            NSColor.white.withAlphaComponent(0.9).setStroke()
            ring.stroke()
        }
    }
}

// MARK: - Content pane

/// A rounded content card. Its drop shadow is drawn by PaneView.
final class CardView: NSView {
    static let radius: CGFloat = 14
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.radius, yRadius: Self.radius)
        Palette.card.setFill()
        path.fill()
        Palette.cardBorder.setStroke()
        path.stroke()
    }
}

/// Draws the card shadows itself so they render in snapshots and never clip.
final class PaneView: NSView {
    var cards: [CardView] = []
    override func layout() { super.layout(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        Palette.pane.setFill()
        bounds.fill()
        let dark = isDark
        for card in cards where !card.isHiddenOrHasHiddenAncestor {
            let rect = convert(card.bounds, from: card)
            let path = NSBezierPath(roundedRect: rect, xRadius: CardView.radius, yRadius: CardView.radius)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.35 : 0.07)
            shadow.shadowOffset = NSSize(width: 0, height: -3)
            shadow.shadowBlurRadius = 12
            shadow.set()
            Palette.card.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

/// A glossy segmented switcher whose violet knob slides between tabs.
final class TabSwitcher: NSView {
    let titles: [String]
    var onChange: ((Int) -> Void)?
    private(set) var selected = 0
    private var position: CGFloat = 0 { didSet { needsDisplay = true } }
    private var timer: Timer?
    private let segmentWidth: CGFloat = 112
    private let inset: CGFloat = 3

    init(titles: [String]) {
        self.titles = titles
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Settings section")
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: CGFloat(titles.count) * segmentWidth + inset * 2, height: 34) }
    override var mouseDownCanMoveWindow: Bool { false }

    func select(_ index: Int, animated: Bool) {
        selected = index
        setAccessibilityValue(titles[index])
        timer?.invalidate()
        guard animated else { position = CGFloat(index); return }
        let start = position, end = CGFloat(index), began = CACurrentMediaTime()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = min(1, (CACurrentMediaTime() - began) / 0.24)
            self.position = start + (end - start) * CGFloat(1 - pow(1 - progress, 3))
            if progress >= 1 { timer.invalidate() }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let index = max(0, min(titles.count - 1, Int((x - inset) / segmentWidth)))
        guard index != selected else { return }
        onChange?(index)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = isDark
        let track = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        (dark ? NSColor.white.withAlphaComponent(0.07) : NSColor.black.withAlphaComponent(0.055)).setFill()
        track.fill()
        Palette.cardBorder.setStroke()
        track.stroke()

        let knob = NSRect(x: inset + position * segmentWidth, y: inset, width: segmentWidth, height: bounds.height - inset * 2)
        let knobPath = NSBezierPath(roundedRect: knob, xRadius: knob.height / 2, yRadius: knob.height / 2)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = Palette.hex(0x4A25D6, 0.45)
        shadow.shadowOffset = NSSize(width: 0, height: -1.5)
        shadow.shadowBlurRadius = 4
        shadow.set()
        NSGradient(starting: Palette.hex(0x9479FF), ending: Palette.hex(0x6B45F5))?.draw(in: knobPath, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        knobPath.addClip()
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0)])?
            .draw(in: NSRect(x: knob.minX, y: knob.midY, width: knob.width, height: knob.height / 2), angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        for (index, title) in titles.enumerated() {
            let onKnob = abs(position - CGFloat(index)) < 0.5
            let text = NSAttributedString(string: title, attributes: [
                .font: roundedFont(13, .semibold),
                .foregroundColor: onKnob ? NSColor.white : Palette.subtle,
            ])
            let size = text.size()
            let midX = inset + (CGFloat(index) + 0.5) * segmentWidth
            text.draw(at: NSPoint(x: midX - size.width / 2, y: bounds.midY - size.height / 2))
        }
    }
}

/// A one-point divider line.
final class HairlineView: NSView {
    var color: NSColor = Palette.hairline
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }
    override func draw(_ dirtyRect: NSRect) { color.setFill(); bounds.fill() }
}

/// A recessed rounded area, used for the Test Mode preview line.
final class WellView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        Palette.well.setFill()
        path.fill()
    }
}

// MARK: - Settings panel

/// The app has no main menu, so ⌘W and Esc are handled here.
final class SettingsWindow: NSWindow {
    var onSelectTab: ((Int) -> Void)?
    override func cancelOperation(_ sender: Any?) { close() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "w": close(); return true
        case "1": onSelectTab?(0); return true
        case "2": onSelectTab?(1); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}

/// Builds and updates the settings window. MailKeys pushes state in through `update`, `updateUsage`
/// and the diagnostics setters, and receives user actions through `Actions`.
final class SettingsPanel: NSObject {
    struct Actions {
        var quit: () -> Void = {}
        var grantAccess: () -> Void
        var togglePause: () -> Void
        var toggleTestMode: () -> Void
        var checkHover: () -> Void
        var checkSpeed: () -> Void
        var resetUsage: () -> Void = {}
    }

    let window: NSWindow
    private let actions: Actions
    private let statusPill = StatusPill()
    private let heroButton: PillButton
    private let testSwitch = NSSwitch()
    private let loginSwitch = NSSwitch()
    private let previewLabel = makeLabel("", size: 12.5, weight: .medium, color: Palette.ink, rounded: true)
    private let previewIcon = NSImageView()
    private let previewKey = KeycapView("e", size: 26)
    private let hoverResult = makeLabel("Checks that hover works in your Mail.", size: 12, color: Palette.subtle, wrapWidth: 236)
    private let speedResult = makeLabel("Times how fast keys respond.", size: 12, color: Palette.subtle, wrapWidth: 236)
    private var keycaps: [String: KeycapView] = [:]
    private let savedLabel = makeLabel("0s", size: 32, weight: .bold, color: .white, rounded: true)
    private let usesLabel = makeLabel("", size: 12, weight: .regular, color: NSColor.white.withAlphaComponent(0.82), rounded: true,
                                      wrapWidth: 184, alignment: .center)
    private let statsPanel = GlassPanel()
    private let practiceTile = IconTile(symbol: "testtube.2", colors: [Palette.hex(0xA78BFF), Palette.hex(0x6B45F5)])
    private let tabs = TabSwitcher(titles: ["Shortcuts", "Advanced"])
    private var pages: [NSView] = []
    private weak var paneView: PaneView?
    private var trusted = true
    private var testMode = false
    private let practiceTitle = makeLabel("Practice first", size: 13.5, weight: .medium, color: Palette.ink, rounded: true)
    private let practiceDetail = makeLabel("", size: 12, color: Palette.subtle, wrapWidth: 230)
    private lazy var practiceButton = PillButton("Try Test Mode", style: .tinted(Palette.violet)) { [weak self] in
        guard let self else { return }
        if self.testMode { self.actions.toggleTestMode() }
        else { self.selectTab(1) }
    }
    private var paused = false
    private var usage = UsageStats()
    private var hintLabels: [String: NSTextField] = [:]
    private let guideHeader = makeLabel("Get started", size: 15, weight: .semibold, color: Palette.ink, rounded: true)
    private let usageDetail = makeLabel("", size: 12, color: Palette.subtle)
    private lazy var resetButton = PillButton("Reset", style: .secondary) { [weak self] in self?.resetTapped() }
    private var pageFits: [NSLayoutConstraint] = []
    private var versionLabel = NSTextField()
    private var footerRow = NSView()

    static let shortcuts: [(key: String, title: String, hint: String)] = [
        ("j", "Next message", "Hold to glide"),
        ("k", "Previous message", "Hold to glide"),
        ("e", "Archive", "Just hover"),
        ("r", "Reply", "To the sender"),
        ("a", "Reply all", "To everyone"),
        ("f", "Forward", "Pass it along"),
        ("c", "Compose", "Fresh message"),
        ("/", "Search", "Jump to search"),
    ]

    init(actions: Actions) {
        self.actions = actions
        heroButton = PillButton("Grant Access", style: .solid, handler: {})
        window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        previewKey.lit = true
        heroButton.target = self
        heroButton.action = #selector(heroTapped)
        window.title = "MailKeys"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = buildRoot()
        (window as? SettingsWindow)?.onSelectTab = { [weak self] in self?.selectTab($0) }
        selectTab(UserDefaults.standard.integer(forKey: "settingsTab"), animated: false)
        updateUsage(UsageStats())
        fitWindow(animated: false)
    }

    // MARK: State

    func update(status: String, tone: StatusPill.Tone, trusted: Bool, paused: Bool, testMode: Bool, preview: String) {
        statusPill.set(status, tone: testMode && tone == .ready ? .testing : tone)
        self.testMode = testMode
        self.trusted = trusted
        self.paused = paused
        refreshGuide()
        if !trusted { heroButton.title = "Grant Access…"; heroButton.style = .solid }
        else if paused { heroButton.title = "Resume Shortcuts"; heroButton.style = .solid }
        else { heroButton.title = "Pause Shortcuts"; heroButton.style = .glass }
        testSwitch.state = testMode ? .on : .off
        var text: String
        let symbol: String
        let tint: NSColor
        if testMode { text = preview == "No shortcut tested yet" ? "Press a shortcut in Mail to try it." : preview; symbol = "eye.fill"; tint = Palette.violet }
        else if !trusted { text = "Grant access to switch shortcuts on."; symbol = "lock.fill"; tint = .systemOrange }
        else if paused { text = "Shortcuts are paused."; symbol = "pause.fill"; tint = .secondaryLabelColor }
        else { text = "Shortcuts are live in Mail."; symbol = "bolt.fill"; tint = .systemGreen }
        if text.hasPrefix("Test: ") { text.removeFirst(6) }
        let parts = text.components(separatedBy: " → ")
        let showsKey = testMode && parts.count == 2
        if showsKey { previewKey.glyph = parts[0]; text = parts[1] }
        previewKey.isHidden = !showsKey
        previewIcon.isHidden = showsKey
        previewLabel.stringValue = text
        previewIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .bold))
        previewIcon.contentTintColor = tint
    }

    func setHoverResult(_ text: String, ok: Bool) { show(text, ok: ok, detail: nil, in: hoverResult) }

    func setSpeedResult(_ text: String, ok: Bool, detail: String? = nil) { show(text, ok: ok, detail: detail, in: speedResult) }

    /// Results read as a sentence: a green checkmark when it passed, never a wall of colored text.
    private func show(_ text: String, ok: Bool, detail: String?, in field: NSTextField) {
        let font = NSFont.systemFont(ofSize: 12)
        let result = NSMutableAttributedString()
        if ok, let check = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Passed")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .bold).applying(.init(paletteColors: [.white, .systemGreen]))) {
            let attachment = NSTextAttachment()
            attachment.image = check
            attachment.bounds = NSRect(x: 0, y: -1.5, width: check.size.width, height: check.size.height)
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: " "))
        }
        result.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: Palette.subtle]))
        field.attributedStringValue = result
        field.toolTip = detail
    }

    func flashKey(_ key: String) { keycaps[key.lowercased()]?.flash() }

    @objc private func heroTapped() { trusted ? actions.togglePause() : actions.grantAccess() }
    @objc private func switchTapped() { actions.toggleTestMode() }
    @objc private func hoverTapped() { actions.checkHover() }
    @objc private func speedTapped() { actions.checkSpeed() }

    // MARK: Layout

    private func buildRoot() -> NSView {
        let root = NSView()
        let hero = buildHero()
        let pane = buildPane()
        for view in [hero, pane] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            hero.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            hero.topAnchor.constraint(equalTo: root.topAnchor),
            hero.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            hero.widthAnchor.constraint(equalToConstant: 280),
            pane.leadingAnchor.constraint(equalTo: hero.trailingAnchor),
            pane.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            pane.topAnchor.constraint(equalTo: root.topAnchor),
            pane.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            pane.widthAnchor.constraint(equalToConstant: 540),
            // The version label shares a centre line with the pane's footer controls.
            versionLabel.centerYAnchor.constraint(equalTo: footerRow.centerYAnchor),
        ])
        return root
    }

    private func buildHero() -> NSView {
        let hero = HeroView()
        let icon = AppIconView()
        let title = makeLabel("MailKeys", size: 28, weight: .bold, color: .white, rounded: true)
        let subtitle = makeLabel("Gmail shortcuts for Apple Mail", size: 13, weight: .regular, color: NSColor.white.withAlphaComponent(0.82), rounded: true)
        let top = NSStackView(views: [icon, title, subtitle, statusPill])
        top.orientation = .vertical
        top.alignment = .centerX
        top.spacing = 6
        top.setCustomSpacing(4, after: icon)
        top.setCustomSpacing(18, after: subtitle)

        let features = buildStats()

        let privacy = makeLabel("Works only inside Mail. Counts shortcuts, never keystrokes or email.",
                                size: 11, weight: .regular, color: NSColor.white.withAlphaComponent(0.75),
                                rounded: true, wrapWidth: 226, alignment: .center)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3"
        versionLabel = makeLabel("Version \(version)", size: 11, weight: .regular,
                                     color: NSColor.white.withAlphaComponent(0.5), rounded: true)
        if let shield = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10.5, weight: .semibold).applying(.init(paletteColors: [NSColor.white.withAlphaComponent(0.8)]))) {
            let attachment = NSTextAttachment()
            attachment.image = shield
            attachment.bounds = NSRect(x: 0, y: -1.5, width: shield.size.width, height: shield.size.height)
            let text = NSMutableAttributedString(attachment: attachment)
            text.append(NSAttributedString(string: " " + privacy.stringValue))
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            text.addAttributes([.font: roundedFont(11, .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.75),
                                .paragraphStyle: style], range: NSRange(location: 0, length: text.length))
            privacy.attributedStringValue = text
        }
        let bottom = NSStackView(views: [privacy, versionLabel])
        bottom.orientation = .vertical
        bottom.alignment = .centerX
        bottom.spacing = 10

        for view in [top, features, heroButton, bottom] { view.translatesAutoresizingMaskIntoConstraints = false; hero.addSubview(view) }
        NSLayoutConstraint.activate([
            top.centerXAnchor.constraint(equalTo: hero.centerXAnchor),
            top.topAnchor.constraint(equalTo: hero.topAnchor, constant: 46),
            features.centerXAnchor.constraint(equalTo: hero.centerXAnchor),
            features.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 24),
            // Everything down to the button keeps a fixed rhythm, so nothing jumps between tabs.
            heroButton.centerXAnchor.constraint(equalTo: hero.centerXAnchor),
            heroButton.topAnchor.constraint(equalTo: features.bottomAnchor, constant: 28),
            // The privacy note and version sit on the bottom edge, level with the pane's footer.
            // Extra height on taller tabs opens up between the button and this note.
            bottom.centerXAnchor.constraint(equalTo: hero.centerXAnchor),
            bottom.topAnchor.constraint(greaterThanOrEqualTo: heroButton.bottomAnchor, constant: 20),
        ])
        return hero
    }

    private func buildStats() -> NSView {
        let panel = statsPanel
        panel.toolTip = "Estimated against doing the same with a mouse, using standard Keystroke-Level Model timings: reach 0.4 s, point 1.1 s, click 0.2 s, keystroke 0.28 s."
        let caption = makeLabel("TIME SAVED", size: 10.5, weight: .semibold, color: NSColor.white.withAlphaComponent(0.72), rounded: true)
        caption.attributedStringValue = NSAttributedString(string: "TIME SAVED", attributes: [
            .font: roundedFont(10.5, .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.72), .kern: 1.2])
        // A fixed slot keeps the panel the same height for the placeholder and the big number.
        let savedSlot = NSView()
        savedLabel.translatesAutoresizingMaskIntoConstraints = false
        savedSlot.addSubview(savedLabel)
        NSLayoutConstraint.activate([
            savedSlot.heightAnchor.constraint(equalToConstant: 42),
            savedLabel.centerYAnchor.constraint(equalTo: savedSlot.centerYAnchor),
            savedLabel.leadingAnchor.constraint(equalTo: savedSlot.leadingAnchor),
            savedLabel.trailingAnchor.constraint(equalTo: savedSlot.trailingAnchor),
        ])
        let stack = NSStackView(views: [caption, savedSlot, usesLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16),
            panel.widthAnchor.constraint(equalToConstant: 216),
        ])
        panel.setAccessibilityElement(true)
        panel.setAccessibilityRole(.group)
        return panel
    }

    func updateUsage(_ usage: UsageStats) {
        self.usage = usage
        let uses = Self.number(usage.totalUses)
        if usage.totalUses == 0 {
            // A big "0s" reads like a failure. Show a calm placeholder until there's real usage.
            savedLabel.font = roundedFont(20, .semibold)
            savedLabel.textColor = NSColor.white.withAlphaComponent(0.8)
            savedLabel.stringValue = "Nothing yet"
            usesLabel.stringValue = "Starts with your first shortcut"
        } else {
            savedLabel.font = roundedFont(32, .bold)
            savedLabel.textColor = .white
            savedLabel.stringValue = UsageStats.format(seconds: usage.secondsSaved)
            usesLabel.stringValue = "across \(uses) shortcut\(usage.totalUses == 1 ? "" : "s")"
        }
        for item in Self.shortcuts {
            let count = usage.counts[item.key] ?? 0
            let hint = NSMutableAttributedString(string: item.hint, attributes: [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: Palette.subtle])
            if count > 0 {
                hint.append(NSAttributedString(string: " · \(Self.compact(count)) use\(count == 1 ? "" : "s")", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium), .foregroundColor: Palette.count]))
            }
            hintLabels[item.key]?.attributedStringValue = hint
        }
        usageDetail.stringValue = usage.totalUses == 0 ? "Nothing counted yet. Counts stay on this Mac."
            : "\(uses) shortcut\(usage.totalUses == 1 ? "" : "s") counted on this Mac."
        resetButton.isEnabled = usage.totalUses > 0
        resetButton.alphaValue = usage.totalUses > 0 ? 1 : 0.45
        let summary = usage.totalUses == 0 ? "No time saved yet" : "\(savedLabel.stringValue) saved across \(uses) shortcuts"
        statsPanel.setAccessibilityLabel("Time saved: \(summary)")
        refreshGuide()
    }

    /// Short form for tight spaces: 9,999 stays exact, then 12.6k, 1.2M.
    static func compact(_ value: Int) -> String {
        if value < 10_000 { return number(value) }
        if value < 1_000_000 { return String(format: "%.1fk", Double(value) / 1000).replacingOccurrences(of: ".0k", with: "k") }
        return String(format: "%.1fM", Double(value) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
    }

    private static func number(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    /// The Shortcuts tab's second card guides whatever comes next: permission, practice, then tips.
    private func refreshGuide() {
        let header: String, title: String, detail: String, symbol: String, colors: [NSColor]
        var button: String?
        if !trusted {
            (header, title, symbol) = ("Get started", "Allow Accessibility", "lock.fill")
            detail = "MailKeys needs it to see which message your pointer is on. Use Grant Access in the sidebar."
            colors = [Palette.hex(0xFFC15A), Palette.hex(0xF08A24)]
        } else if testMode {
            (header, title, symbol) = ("Test Mode", "Test Mode is on", "testtube.2")
            detail = "Press keys in Mail. They light up here and nothing happens."
            colors = [Palette.hex(0xA78BFF), Palette.hex(0x6B45F5)]
            button = "Turn Off"
        } else if usage.totalUses == 0 {
            (header, title, symbol) = ("Get started", "Practice first", "testtube.2")
            detail = "Test Mode lights up these keys without touching your mail."
            colors = [Palette.hex(0xA78BFF), Palette.hex(0x6B45F5)]
            button = "Try Test Mode"
        } else if usage.counts["e"] == nil {
            (header, title, symbol) = ("Tip", "Archive without clicking", "cursorarrow.rays")
            detail = "Hover any message and press E. MailKeys then moves you to the next one."
            colors = [Palette.hex(0xFFB458), Palette.hex(0xF0612E)]
        } else if usage.counts["j"] == nil && usage.counts["k"] == nil {
            (header, title, symbol) = ("Tip", "Glide through your inbox", "arrow.up.arrow.down")
            detail = "Hold J or K to move through messages, thirty a second. Let go to stop."
            colors = [Palette.hex(0x7FB2FF), Palette.hex(0x4D6BFF)]
        } else if usage.counts["/"] == nil {
            (header, title, symbol) = ("Tip", "Search in a keystroke", "magnifyingglass")
            detail = "Press / to jump straight to Mail’s search field."
            colors = [Palette.hex(0x7FB2FF), Palette.hex(0x4D6BFF)]
        } else {
            (header, title, symbol) = ("Tip", "You’re flying", "sparkles")
            detail = "Every shortcut is in your hands now. Hold J to glide when the inbox is long."
            colors = [Palette.hex(0x4FE0B0), Palette.hex(0x12A879)]
        }
        guideHeader.stringValue = header
        practiceTitle.stringValue = title
        practiceDetail.stringValue = detail
        practiceTile.update(symbol: symbol, colors: colors)
        practiceButton.isHidden = button == nil
        if let button { practiceButton.title = button }
        practiceDetail.preferredMaxLayoutWidth = button == nil ? 320 : 230
    }

    @objc private func resetTapped() { actions.resetUsage() }

    private func buildPane() -> NSView {
        let pane = PaneView()
        let shortcuts = card(buildShortcuts())
        let test = card(buildTestMode())
        let diagnostics = card(buildDiagnostics())
        let practice = card(buildPractice())
        let usageCard = card(buildUsage())
        pane.cards = [shortcuts, practice, test, diagnostics, usageCard]
        paneView = pane
        let guideTitle = NSStackView(views: [guideHeader])
        guideTitle.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        pages = [
            page([sectionTitle("Keys"), shortcuts, guideTitle, practice]),
            page([sectionTitle("Try it safely"), test, sectionTitle("Diagnostics"), diagnostics, sectionTitle("Usage"), usageCard]),
        ]
        tabs.onChange = { [weak self] in self?.selectTab($0) }
        tabs.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.centerXAnchor.constraint(equalTo: pane.centerXAnchor),
            tabs.topAnchor.constraint(equalTo: pane.topAnchor, constant: 12),
        ])
        let footer = buildFooter()
        footer.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(footer)
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 32),
            footer.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -28),
            footer.bottomAnchor.constraint(equalTo: pane.bottomAnchor, constant: -18),
        ])
        for page in pages {
            page.translatesAutoresizingMaskIntoConstraints = false
            pane.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 28),
                page.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -28),
                page.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 20),
            ])
            // Only the visible page sizes the window, so each tab gets its own height.
            pageFits.append(footer.topAnchor.constraint(greaterThanOrEqualTo: page.bottomAnchor, constant: 20))
        }
        return pane
    }

    private func buildFooter() -> NSView {
        loginSwitch.controlSize = .small
        loginSwitch.target = self
        loginSwitch.action = #selector(loginTapped)
        loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginSwitch.setAccessibilityLabel("Open MailKeys at login")
        let label = makeLabel("Open at login", size: 12, color: Palette.subtle)
        let quit = PillButton("Quit MailKeys", style: .secondary) { [weak self] in self?.actions.quit() }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [loginSwitch, label, spacer, quit])
        row.spacing = 8
        footerRow = row
        return row
    }

    @objc private func loginTapped() {
        do {
            if loginSwitch.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSSound.beep()
        }
        loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func page(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        for view in views where view is CardView {
            stack.setCustomSpacing(22, after: view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    func selectTab(_ index: Int, animated: Bool = true) {
        guard pages.indices.contains(index) else { return }
        tabs.select(index, animated: animated)
        for (i, page) in pages.enumerated() { page.isHidden = i != index }
        for (i, fit) in pageFits.enumerated() { fit.isActive = i == index }
        paneView?.needsDisplay = true
        UserDefaults.standard.set(index, forKey: "settingsTab")
        fitWindow(animated: animated)
    }

    /// Resizes the window to the visible tab, keeping its top edge still like System Settings.
    func fitWindow(animated: Bool) {
        guard let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        guard size.height > 0, abs(size.height - content.frame.height) > 0.5 || abs(size.width - content.frame.width) > 0.5 else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }

    private func sectionTitle(_ text: String) -> NSView {
        let label = makeLabel(text, size: 15, weight: .semibold, color: Palette.ink, rounded: true)
        let wrapper = NSStackView(views: [label])
        wrapper.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        return wrapper
    }

    private func card(_ content: NSView) -> CardView {
        let card = CardView()
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        return card
    }

    private func buildShortcuts() -> NSView {
        func cell(_ item: (key: String, title: String, hint: String)) -> NSView {
            let keycap = KeycapView(item.key)
            keycaps[item.key] = keycap
            let title = makeLabel(item.title, size: 13, weight: .medium, color: Palette.ink, rounded: true)
            let hint = makeLabel(item.hint, size: 11.5, color: Palette.subtle)
            hintLabels[item.key] = hint
            let text = NSStackView(views: [title, hint])
            text.orientation = .vertical
            text.alignment = .leading
            text.spacing = 1
            let row = NSStackView(views: [keycap, text])
            row.spacing = 10
            return row
        }
        let items = Self.shortcuts
        let rows = stride(from: 0, to: items.count, by: 2).map { [cell(items[$0]), cell(items[$0 + 1])] }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.column(at: 0).width = 216

        return grid
    }

    private func buildPractice() -> NSView {
        let tile = practiceTile
        let text = NSStackView(views: [practiceTitle, practiceDetail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [tile, text, spacer, practiceButton])
        row.spacing = 12
        return row
    }

    private func buildTestMode() -> NSView {
        let tile = IconTile(symbol: "testtube.2", colors: [Palette.hex(0xA78BFF), Palette.hex(0x6B45F5)])
        let title = makeLabel("Test Mode", size: 13.5, weight: .medium, color: Palette.ink, rounded: true)
        let detail = makeLabel("Keys light up here instead of acting in Mail.", size: 12, color: Palette.subtle)
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        testSwitch.target = self
        testSwitch.action = #selector(switchTapped)
        testSwitch.setAccessibilityLabel("Test Mode")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [tile, text, spacer, testSwitch])
        row.spacing = 12

        let well = WellView()
        let inner = NSStackView(views: [previewIcon, previewKey, previewLabel])
        inner.spacing = 7
        inner.translatesAutoresizingMaskIntoConstraints = false
        well.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: well.leadingAnchor, constant: 10),
            inner.trailingAnchor.constraint(lessThanOrEqualTo: well.trailingAnchor, constant: -12),
            inner.centerYAnchor.constraint(equalTo: well.centerYAnchor),
            well.heightAnchor.constraint(equalToConstant: 42),
        ])
        let stack = NSStackView(views: [row, well])
        stack.orientation = .vertical
        stack.spacing = 12
        for view in [row, well] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    private func buildUsage() -> NSView {
        let tile = IconTile(symbol: "chart.bar.fill", colors: [Palette.hex(0x7FB2FF), Palette.hex(0x4D6BFF)])
        let title = makeLabel("Shortcut counts", size: 13.5, weight: .medium, color: Palette.ink, rounded: true)
        let text = NSStackView(views: [title, usageDetail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [tile, text, spacer, resetButton])
        row.spacing = 12
        return row
    }

    private func buildDiagnostics() -> NSView {
        func row(symbol: String, colors: [NSColor], title: String, result: NSTextField, button: String, action: Selector) -> NSView {
            let tile = IconTile(symbol: symbol, colors: colors)
            let label = makeLabel(title, size: 13.5, weight: .medium, color: Palette.ink, rounded: true)
            let text = NSStackView(views: [label, result])
            text.orientation = .vertical
            text.alignment = .leading
            text.spacing = 2
            let pill = PillButton(button, style: .secondary, handler: {})
            pill.target = self
            pill.action = action
            let spacer = NSView()
            spacer.setContentHuggingPriority(.init(1), for: .horizontal)
            let row = NSStackView(views: [tile, text, spacer, pill])
            row.spacing = 12
            row.alignment = .centerY
            return row
        }
        let hover = row(symbol: "cursorarrow.rays", colors: [Palette.hex(0xFFB458), Palette.hex(0xF0612E)],
                        title: "Hover support", result: hoverResult, button: "Check", action: #selector(hoverTapped))
        let speed = row(symbol: "speedometer", colors: [Palette.hex(0x4FE0B0), Palette.hex(0x12A879)],
                        title: "Responsiveness", result: speedResult, button: "Measure", action: #selector(speedTapped))
        let stack = NSStackView(views: [hover, HairlineView(), speed])
        stack.orientation = .vertical
        stack.spacing = 12
        for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    // MARK: Snapshots

    /// Draws the app icon on Apple's macOS grid (an 824 pt tile on a 1024 pt canvas) and writes a PNG.
    static func renderIcon(to path: String, pixels: Int = 1024) {
        try? iconRep(pixels: pixels)?.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    static func iconRep(pixels: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: 1024, height: 1024)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        drawIcon()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func drawIcon() {
        let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
        let tilePath = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

        NSGraphicsContext.saveGraphicsState()
        let drop = NSShadow()
        drop.shadowColor = NSColor.black.withAlphaComponent(0.32)
        drop.shadowOffset = NSSize(width: 0, height: -12)
        drop.shadowBlurRadius = 24
        drop.set()
        Palette.hex(0x6B45F5).setFill()
        tilePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        tilePath.addClip()
        NSGradient(colors: [Palette.hex(0x4D6BFF), Palette.hex(0x7A3EF0), Palette.hex(0xD6409C)],
                   atLocations: [0, 0.55, 1], colorSpace: .sRGB)?.draw(in: tile, angle: -60)
        blob(at: NSPoint(x: tile.minX + 60, y: tile.maxY - 40), radius: 520, color: Palette.hex(0x45D8FF, 0.55))
        blob(at: NSPoint(x: tile.maxX, y: tile.minY + 40), radius: 520, color: Palette.hex(0xFF9B57, 0.55))
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])?
            .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 2, dy: 2), xRadius: 184, yRadius: 184)
        rim.lineWidth = 4
        NSColor.white.withAlphaComponent(0.22).setStroke()
        rim.stroke()

        // Envelope.
        let config = NSImage.SymbolConfiguration(pointSize: 330, weight: .semibold).applying(.init(paletteColors: [.white]))
        if let envelope = NSImage(systemSymbolName: "envelope.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let size = envelope.size
            NSGraphicsContext.saveGraphicsState()
            let lift = NSShadow()
            lift.shadowColor = Palette.hex(0x24095E, 0.35)
            lift.shadowOffset = NSSize(width: 0, height: -14)
            lift.shadowBlurRadius = 28
            lift.set()
            envelope.draw(in: NSRect(x: 452 - size.width / 2, y: 590 - size.height / 2, width: size.width, height: size.height))
            NSGraphicsContext.restoreGraphicsState()
        }

        // Glossy E key.
        let key = NSRect(x: 556, y: 222, width: 268, height: 268)
        NSGraphicsContext.saveGraphicsState()
        let keyShadow = NSShadow()
        keyShadow.shadowColor = Palette.hex(0x24095E, 0.5)
        keyShadow.shadowOffset = NSSize(width: 0, height: -14)
        keyShadow.shadowBlurRadius = 26
        keyShadow.set()
        Palette.hex(0xC9C3EE).setFill()
        NSBezierPath(roundedRect: key, xRadius: 64, yRadius: 64).fill()
        NSGraphicsContext.restoreGraphicsState()
        var face = key.insetBy(dx: 8, dy: 0)
        face.origin.y += 24
        face.size.height -= 32
        let facePath = NSBezierPath(roundedRect: face, xRadius: 56, yRadius: 56)
        NSGradient(starting: .white, ending: Palette.hex(0xEDEAFB))?.draw(in: facePath, angle: -90)
        let glyph = NSAttributedString(string: "E", attributes: [.font: roundedFont(140, .bold), .foregroundColor: Palette.hex(0x6B45F5)])
        let glyphSize = glyph.size()
        glyph.draw(at: NSPoint(x: face.midX - glyphSize.width / 2, y: face.midY - glyphSize.height / 2 + 4))
    }

    /// Renders the panel offscreen in several states with sample data. Handy for checking the design
    /// in light and dark mode without granting screen recording access.
    static func renderSnapshots(to directory: String) {
        let noop = Actions(quit: {}, grantAccess: {}, togglePause: {}, toggleTestMode: {}, checkHover: {}, checkSpeed: {})
        let states: [(name: String, dark: Bool, configure: (SettingsPanel) -> Void)] = [
            ("needs-access-light", false, { $0.update(status: "Needs Accessibility permission", tone: .attention, trusted: false, paused: false, testMode: true, preview: "No shortcut tested yet") }),
            ("ready-light", false, { $0.update(status: "Ready: hover a message and press e", tone: .ready, trusted: true, paused: false, testMode: false, preview: "") }),
            ("ready-dark", true, { $0.update(status: "Ready: hover a message and press e", tone: .ready, trusted: true, paused: false, testMode: false, preview: "") }),
            ("testing-dark", true, {
                $0.update(status: "Ready: hover a message and press e", tone: .ready, trusted: true, paused: false, testMode: true, preview: "Test: e → Archive hovered message")
                $0.keycaps["e"]?.lit = true
                $0.setHoverResult("Verified. Hover archive works here.", ok: true)
                $0.setSpeedResult("Instant. About 0.4 ms per key.", ok: true)
            }),
            ("advanced-light", false, { $0.update(status: "Ready: hover a message and press e", tone: .ready, trusted: true, paused: false, testMode: false, preview: "") }),
            ("paused-light", false, { $0.update(status: "Paused", tone: .paused, trusted: true, paused: true, testMode: false, preview: "") }),
        ]
        for state in states {
            let panel = SettingsPanel(actions: noop)
            panel.window.appearance = NSAppearance(named: state.dark ? .darkAqua : .aqua)
            if !state.name.hasPrefix("needs") {
                panel.updateUsage(UsageStats(counts: ["e": 812, "j": 1650, "k": 640, "r": 120, "a": 40, "f": 22, "c": 31, "/": 54]))
            }
            panel.selectTab(state.name.hasPrefix("ready") || state.name.hasPrefix("needs") ? 0 : 1, animated: false)
            state.configure(panel)
            guard let view = panel.window.contentView else { continue }
            view.layoutSubtreeIfNeeded()
            if let fitting = panel.window.contentView?.fittingSize { panel.window.setContentSize(fitting) }
            view.layoutSubtreeIfNeeded()
            let bounds = view.bounds
            guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { continue }
            rep.size = bounds.size
            NSAppearance(named: state.dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                view.cacheDisplay(in: bounds, to: rep)
            }
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(state.name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("wrote \(url.path) \(Int(bounds.width))x\(Int(bounds.height))")
        }
    }
}
