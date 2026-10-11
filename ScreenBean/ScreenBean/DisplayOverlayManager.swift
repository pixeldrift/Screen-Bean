//
//  DisplayOverlayManager.swift
//  ScreenBean
//
//  Draws on the real screens: a colored border around the display selected in
//  the workspace, identify mode (each display filled with its gradient, letter
//  and caption, like the virtual displays), and a wallpaper preview spanning
//  all displays.
//
//  Identify and preview cover the whole screen, so they end on the first mouse
//  click or key press, which keeps them from locking you out of the interface.
//

import Cocoa

final class DisplayOverlayManager {
    /// Fill every real display with its identity (gradient, letter and caption).
    var identifyEnabled = false {
        didSet {
            refresh()
            updateMonitors()
        }
    }
    /// In identify mode, leave the primary display (where the app usually sits) clear.
    var excludePrimary = false { didSet { refresh() } }

    /// Per-display wallpaper slices shown full screen while previewing; nil when not previewing.
    private(set) var previewImages: [CGDirectDisplayID: CGImage]?

    /// Called after a click or key press ends identify or preview, so buttons can reset.
    var onModesStopped: (() -> Void)?
    /// Views (the mode buttons) where a click shouldn't end the modes, because the button handles it.
    var clickThroughViews: [NSView] = []

    private var identities: [DisplayIdentity] = []
    private var selectedID: CGDirectDisplayID?
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var globalMonitor: Any?
    private var localMonitor: Any?

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

    func showPreview(_ images: [CGDirectDisplayID: CGImage]) {
        previewImages = images
        refresh()
        updateMonitors()
    }

    func hidePreview() {
        previewImages = nil
        refresh()
        updateMonitors()
    }

    /// Removes every overlay.
    func hideAll() {
        stopMonitors()
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
    }

    // MARK: - Windows

    private func refresh() {
        var wanted = Set<CGDirectDisplayID>()
        for identity in identities {
            let showsIdentity = identifyEnabled && !(excludePrimary && identity.isPrimary)
            let showsBorder = identity.id == selectedID
            let preview = previewImages?[identity.id]
            guard showsIdentity || showsBorder || preview != nil, let screen = NSScreen.screen(forDisplayID: identity.id) else { continue }
            wanted.insert(identity.id)
            let window = windows[identity.id] ?? makeWindow()
            windows[identity.id] = window
            window.setFrame(screen.frame, display: false)
            (window.contentView as? OverlayView)?.configure(identity, showsIdentity: showsIdentity, showsBorder: showsBorder, preview: preview)
            window.orderFrontRegardless()
        }
        for id in Array(windows.keys) where !wanted.contains(id) {
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

    // MARK: - Ending on input

    private var modesActive: Bool { identifyEnabled || previewImages != nil }

    private func updateMonitors() {
        modesActive ? startMonitors() : stopMonitors()
    }

    private func startMonitors() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        // Input going to other apps. Key events here need the Input Monitoring permission; clicks don't.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            DispatchQueue.main.async { self?.stopModes() }
        }
        // Input going to Screen Bean itself.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            if let self, !self.isClickOnModeButton(event) { self.stopModes() }
            return event
        }
    }

    private func stopMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func isClickOnModeButton(_ event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown else { return false }
        return clickThroughViews.contains { view in
            guard view.window != nil, event.window === view.window else { return false }
            return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
        }
    }

    private func stopModes() {
        guard modesActive else { return }
        identifyEnabled = false
        previewImages = nil
        refresh()
        stopMonitors()
        onModesStopped?()
    }
}

/// The content of one overlay window.
private final class OverlayView: NSView {
    private var identity: DisplayIdentity?
    private var showsIdentity = false
    private var showsBorder = false
    private var preview: CGImage?

    func configure(_ identity: DisplayIdentity, showsIdentity: Bool, showsBorder: Bool, preview: CGImage?) {
        self.identity = identity
        self.showsIdentity = showsIdentity
        self.showsBorder = showsBorder
        self.preview = preview
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let identity, let context = NSGraphicsContext.current?.cgContext else { return }
        let color = NSColor(displayHex: identity.colorHex)

        if let preview {
            context.interpolationQuality = .high
            context.draw(preview, in: bounds)
        } else if showsIdentity, let gradient = DisplayGradient.make(hex: identity.colorHex) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: bounds.maxX, y: bounds.maxY),
                end: CGPoint(x: bounds.minX, y: bounds.minY),
                options: []
            )
        }
        if showsIdentity { drawIdentityMarks(identity) }
        if showsBorder { drawBorder(color) }
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

    /// The same faint circle and letter, and name, resolution and size, as on the virtual display.
    private func drawIdentityMarks(_ identity: DisplayIdentity) {
        let base = min(bounds.width, bounds.height)
        let diameter = base * 0.5
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        NSColor.white.withAlphaComponent(0.32).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)).fill()

        let ink = NSColor.black.withAlphaComponent(0.7)
        let letterAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: diameter * 0.62, weight: .bold), .foregroundColor: ink]
        let letterSize = (identity.label as NSString).size(withAttributes: letterAttributes)
        (identity.label as NSString).draw(at: CGPoint(x: center.x - letterSize.width / 2, y: center.y - letterSize.height / 2), withAttributes: letterAttributes)

        // Caption lines, top-aligned in the lower quarter.
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        func attributes(_ size: CGFloat, _ weight: NSFont.Weight) -> [NSAttributedString.Key: Any] {
            [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink, .paragraphStyle: paragraph]
        }
        let lines: [(String, [NSAttributedString.Key: Any])] = [
            (identity.name, attributes(max(base * 0.035, 16), .semibold)),
            (identity.resolutionText, attributes(max(base * 0.026, 12), .regular)),
            (identity.sizeText, attributes(max(base * 0.026, 12), .regular))
        ]
        var top = bounds.height / 4
        for (text, attrs) in lines {
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(in: CGRect(x: bounds.minX + 16, y: top - size.height, width: bounds.width - 32, height: size.height), withAttributes: attrs)
            top -= size.height
        }
    }
}
