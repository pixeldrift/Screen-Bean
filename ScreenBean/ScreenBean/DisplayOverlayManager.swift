//
//  DisplayOverlayManager.swift
//  ScreenBean
//
//  Draws on the real screens: a colored border around the display selected in
//  the workspace, and (in identify mode) the same lettered circle and caption
//  shown on the virtual displays. Overlays are click-through, so they stay up
//  while you work until switched off.
//

import Cocoa

final class DisplayOverlayManager {
    /// Show the letter, name and sizes on every real display.
    var identifyEnabled = false { didSet { refresh() } }
    /// In identify mode, leave the primary display (where the app usually sits) clear.
    var excludePrimary = false { didSet { refresh() } }

    private var identities: [DisplayIdentity] = []
    private var selectedID: CGDirectDisplayID?
    private var windows: [CGDirectDisplayID: NSWindow] = [:]

    init() {
        // Follow displays being added, removed or rearranged.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    /// Call whenever the displays, their appearance or the selection change.
    func update(displays: [DisplayInfo], selectedID: CGDirectDisplayID?) {
        identities = DisplayIdentity.identities(for: displays)
        self.selectedID = selectedID
        refresh()
    }

    /// Removes every overlay.
    func hideAll() {
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
    }

    private func refresh() {
        var wanted = Set<CGDirectDisplayID>()
        for identity in identities {
            let showsIdentity = identifyEnabled && !(excludePrimary && identity.isPrimary)
            let showsBorder = identity.id == selectedID
            guard showsIdentity || showsBorder, let screen = NSScreen.screen(forDisplayID: identity.id) else { continue }
            wanted.insert(identity.id)
            let window = windows[identity.id] ?? makeWindow()
            windows[identity.id] = window
            window.setFrame(screen.frame, display: false)
            (window.contentView as? OverlayView)?.configure(identity, showsIdentity: showsIdentity, showsBorder: showsBorder)
            window.orderFrontRegardless()
        }
        for id in windows.keys where !wanted.contains(id) {
            windows[id]?.orderOut(nil)
            windows[id] = nil
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = OverlayView()
        return window
    }
}

/// The content of one overlay window.
private final class OverlayView: NSView {
    private var identity: DisplayIdentity?
    private var showsIdentity = false
    private var showsBorder = false

    func configure(_ identity: DisplayIdentity, showsIdentity: Bool, showsBorder: Bool) {
        self.identity = identity
        self.showsIdentity = showsIdentity
        self.showsBorder = showsBorder
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let identity else { return }
        let color = NSColor(displayHex: identity.colorHex)
        if showsBorder { drawBorder(color) }
        if showsIdentity { drawIdentity(identity, color: color) }
    }

    /// A bold border in the display's color with a thin white edge so it shows on any content.
    private func drawBorder(_ color: NSColor) {
        let width: CGFloat = 10
        let outer = NSBezierPath(rect: bounds.insetBy(dx: width / 2, dy: width / 2))
        outer.lineWidth = width
        color.setStroke()
        outer.stroke()
        let inner = NSBezierPath(rect: bounds.insetBy(dx: width + 1, dy: width + 1))
        inner.lineWidth = 2
        NSColor.white.withAlphaComponent(0.85).setStroke()
        inner.stroke()
    }

    private func drawIdentity(_ identity: DisplayIdentity, color: NSColor) {
        let base = min(bounds.width, bounds.height)
        let diameter = base * 0.34
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let circle = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        color.withAlphaComponent(0.88).setFill()
        NSBezierPath(ovalIn: circle).fill()

        let letterAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: diameter * 0.62, weight: .bold),
            .foregroundColor: NSColor.black.withAlphaComponent(0.7)
        ]
        let letterSize = (identity.label as NSString).size(withAttributes: letterAttributes)
        (identity.label as NSString).draw(at: CGPoint(x: center.x - letterSize.width / 2, y: center.y - letterSize.height / 2), withAttributes: letterAttributes)

        // Name, resolution and size on a dark pill, centered in the lower quarter.
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        func attributes(_ size: CGFloat, _ weight: NSFont.Weight) -> [NSAttributedString.Key: Any] {
            [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: NSColor.white, .paragraphStyle: paragraph]
        }
        let lines: [(String, [NSAttributedString.Key: Any])] = [
            (identity.name, attributes(max(base * 0.035, 16), .semibold)),
            (identity.resolutionText, attributes(max(base * 0.026, 12), .regular)),
            (identity.sizeText, attributes(max(base * 0.026, 12), .regular))
        ]
        let sizes = lines.map { ($0.0 as NSString).size(withAttributes: $0.1) }
        let padding = max(base * 0.015, 8)
        let textWidth = sizes.map(\.width).max() ?? 0
        let textHeight = sizes.reduce(0) { $0 + $1.height }
        let pill = CGRect(
            x: bounds.midX - textWidth / 2 - padding * 1.5,
            y: bounds.height / 8 - textHeight / 2 - padding,
            width: textWidth + padding * 3,
            height: textHeight + padding * 2
        )
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: pill, xRadius: padding, yRadius: padding).fill()
        var top = pill.maxY - padding
        for (index, line) in lines.enumerated() {
            let size = sizes[index]
            (line.0 as NSString).draw(in: CGRect(x: pill.minX, y: top - size.height, width: pill.width, height: size.height), withAttributes: line.1)
            top -= size.height
        }
    }
}
