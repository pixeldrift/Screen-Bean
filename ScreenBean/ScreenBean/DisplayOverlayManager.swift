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
    private var guides: [ResolvedGuide] = []
    private var panels: [CGDirectDisplayID: CGRect] = [:]
    private var selectedIDs: Set<CGDirectDisplayID> = []
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
    /// `guides` are in physical inches and `panels` give each display's place on that canvas,
    /// which is how a guide is mapped onto every real screen it crosses.
    func update(displays: [DisplayInfo], selectedIDs: Set<CGDirectDisplayID>, guides: [ResolvedGuide], panels: [CGDirectDisplayID: CGRect]) {
        identities = DisplayIdentity.identities(for: displays)
        self.selectedIDs = selectedIDs
        self.guides = guides
        self.panels = panels
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
            let showsBorder = selectedIDs.contains(identity.id)
            let preview = previewImages?[identity.id]
            let showsGuides = !guides.isEmpty && panels[identity.id] != nil
            guard showsIdentity || showsBorder || preview != nil || showsGuides, let screen = NSScreen.screen(forDisplayID: identity.id) else { continue }
            wanted.insert(identity.id)
            let window = windows[identity.id] ?? makeWindow()
            windows[identity.id] = window
            window.setFrame(screen.frame, display: false)
            (window.contentView as? OverlayView)?.configure(identity, showsIdentity: showsIdentity, showsBorder: showsBorder, preview: preview, guides: showsGuides ? guides : [], panel: panels[identity.id])
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
    private var guides: [ResolvedGuide] = []
    private var panel: CGRect?

    func configure(_ identity: DisplayIdentity, showsIdentity: Bool, showsBorder: Bool, preview: CGImage?, guides: [ResolvedGuide], panel: CGRect?) {
        self.identity = identity
        self.guides = guides
        self.panel = panel
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
        drawGuides()
        if showsBorder { drawBorder(color) }
    }

    /// Guides in physical inches, mapped onto this screen through the display's place on the canvas.
    private func drawGuides() {
        guard let panel, panel.width > 0, panel.height > 0 else { return }
        for guide in guides {
            let path = NSBezierPath()
            switch guide.axis {
            case .vertical:
                let x = bounds.minX + CGFloat((guide.position - Double(panel.minX)) / Double(panel.width)) * bounds.width
                guard x >= bounds.minX, x <= bounds.maxX else { continue }
                path.move(to: CGPoint(x: x, y: bounds.minY)); path.line(to: CGPoint(x: x, y: bounds.maxY))
            case .horizontal:
                let y = bounds.minY + CGFloat((guide.position - Double(panel.minY)) / Double(panel.height)) * bounds.height
                guard y >= bounds.minY, y <= bounds.maxY else { continue }
                path.move(to: CGPoint(x: bounds.minX, y: y)); path.line(to: CGPoint(x: bounds.maxX, y: y))
            }
            NSColor.black.withAlphaComponent(0.45).setStroke()
            path.lineWidth = 4
            path.stroke()
            guide.color.setStroke()
            path.lineWidth = 2
            if !guide.isCustom { path.setLineDash([10, 6], count: 2, phase: 0) }
            path.stroke()
        }
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
        // Centered between the bottom of the circle and the bottom of the screen.
        let sizes = lines.map { ($0.0 as NSString).size(withAttributes: $0.1) }
        let blockHeight = sizes.reduce(0) { $0 + $1.height }
        var top = (center.y - diameter / 2) / 2 + blockHeight / 2
        for (index, line) in lines.enumerated() {
            let size = sizes[index]
            (line.0 as NSString).draw(in: CGRect(x: bounds.minX + 16, y: top - size.height, width: bounds.width - 32, height: size.height), withAttributes: line.1)
            top -= size.height
        }
    }
}
