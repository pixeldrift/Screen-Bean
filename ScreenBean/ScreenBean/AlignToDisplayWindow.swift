//
//  AlignToDisplayWindow.swift
//  ScreenBean
//
//  The editor behind "Align to Display…" on the reference image. Mark the four corners of a
//  display in the photo, or draw a line and enter how long it really is, and Match scales and
//  places the image in the workspace to fit.
//

import Cocoa

/// A display the photo can be matched to.
struct AlignTarget {
    let id: CGDirectDisplayID
    let label: String
    let name: String
    /// The screen in workspace inches; the origin is its lower-left corner.
    let rect: CGRect
}

// MARK: - Canvas

/// Shows the photo and lets points be placed and dragged on it. Points are in image points, origin at the top left.
final class AlignCanvasView: NSView {
    var image: NSImage? { didSet { hasFitted = false; needsLayout = true; needsDisplay = true } }
    var maxPoints = 4 { didSet { points = Array(points.prefix(maxPoints)); needsDisplay = true } }
    /// Four points are a display's corners, joined as a box and named once all four are down; two points are a line.
    var marksCorners = true { didSet { needsDisplay = true } }
    var onPointsChanged: (() -> Void)?

    private(set) var points: [CGPoint] = []
    private var scale: CGFloat = 1
    private var offset = CGPoint.zero
    private var hasFitted = false
    private var activeIndex: Int?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    // MARK: Points

    func clearPoints() {
        points = []
        activeIndex = nil
        needsDisplay = true
        onPointsChanged?()
    }

    func removeLastPoint() {
        guard !points.isEmpty else { return }
        points.removeLast()
        needsDisplay = true
        onPointsChanged?()
    }

    // MARK: Coordinates

    private func viewPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: offset.x + p.x * scale, y: offset.y + p.y * scale) }

    private func imagePoint(_ v: CGPoint) -> CGPoint {
        guard let size = image?.size else { return v }
        let p = CGPoint(x: (v.x - offset.x) / scale, y: (v.y - offset.y) / scale)
        return CGPoint(x: min(max(p.x, 0), size.width), y: min(max(p.y, 0), size.height))
    }

    /// Fits the whole photo in the view.
    func fit() {
        guard let size = image?.size, size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        scale = max(min((bounds.width - 40) / size.width, (bounds.height - 40) / size.height), 0.001)
        offset = CGPoint(x: (bounds.width - size.width * scale) / 2, y: (bounds.height - size.height * scale) / 2)
        hasFitted = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if !hasFitted { fit() }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.12, alpha: 1).setFill()
        bounds.fill()
        guard let image else { return }
        let rect = CGRect(origin: offset, size: CGSize(width: image.size.width * scale, height: image.size.height * scale))
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

        let marks = points.map(viewPoint)
        guard !marks.isEmpty else { return }
        let accent = NSColor.systemYellow
        // Once all four corners are down, they are joined in box order and named, however they were clicked.
        let corners = marksCorners ? ReferenceAlignment.cornerOrder(of: points) : nil
        let joinOrder = corners ?? Array(marks.indices)
        if marks.count > 1 {
            let path = NSBezierPath()
            path.move(to: marks[joinOrder[0]])
            for index in joinOrder.dropFirst() { path.line(to: marks[index]) }
            if corners != nil {
                path.close()
                accent.withAlphaComponent(0.15).setFill()
                path.fill()
            }
            path.lineWidth = 3
            NSColor.black.withAlphaComponent(0.6).setStroke()
            path.stroke()
            path.lineWidth = 1.5
            accent.setStroke()
            path.stroke()
        }
        let names = ["TL", "TR", "BR", "BL"]
        for (index, mark) in marks.enumerated() {
            let ring = NSBezierPath(ovalIn: CGRect(x: mark.x - 7, y: mark.y - 7, width: 14, height: 14))
            ring.lineWidth = 3
            NSColor.black.withAlphaComponent(0.6).setStroke()
            ring.stroke()
            ring.lineWidth = 1.5
            (index == activeIndex ? NSColor.white : accent).setStroke()
            ring.stroke()
            // A small cross at the exact spot.
            let cross = NSBezierPath()
            cross.move(to: CGPoint(x: mark.x - 3, y: mark.y)); cross.line(to: CGPoint(x: mark.x + 3, y: mark.y))
            cross.move(to: CGPoint(x: mark.x, y: mark.y - 3)); cross.line(to: CGPoint(x: mark.x, y: mark.y + 3))
            cross.lineWidth = 1
            accent.setStroke()
            cross.stroke()
            // Corners are named by where they turn out to be; anything else by the order clicked.
            var name = "\(index + 1)"
            if let corners, let role = corners.firstIndex(of: index) { name = names[role] }
            let text = NSAttributedString(string: name, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.6)
            ])
            text.draw(at: CGPoint(x: mark.x + 10, y: mark.y - 18))
        }
    }

    // MARK: Mouse and keys

    /// The marked point within a few points of `v`, the nearest if several are.
    private func pointIndex(near v: CGPoint) -> Int? {
        var best: Int?
        var bestDistance: CGFloat = 11
        for index in points.indices {
            let spot = viewPoint(points[index])
            let distance = hypot(spot.x - v.x, spot.y - v.y)
            if distance <= bestDistance { best = index; bestDistance = distance }
        }
        return best
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard image != nil else { return }
        let v = convert(event.locationInWindow, from: nil)
        if let index = pointIndex(near: v) {
            activeIndex = index
        } else if points.count < maxPoints {
            points.append(imagePoint(v))
            activeIndex = points.count - 1
            onPointsChanged?()
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let activeIndex, points.indices.contains(activeIndex) else { return }
        points[activeIndex] = imagePoint(convert(event.locationInWindow, from: nil))
        needsDisplay = true
        onPointsChanged?()
    }

    override func mouseUp(with event: NSEvent) {
        activeIndex = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        // Delete takes back the last point.
        if event.keyCode == 51 || event.keyCode == 117 { removeLastPoint() } else { super.keyDown(with: event) }
    }

    /// Zooms about a point in the view, keeping that spot of the photo where it is.
    private func zoom(by factor: CGFloat, about anchor: CGPoint) {
        let before = CGPoint(x: (anchor.x - offset.x) / scale, y: (anchor.y - offset.y) / scale)
        scale = min(max(scale * factor, 0.01), 40)
        offset = CGPoint(x: anchor.x - before.x * scale, y: anchor.y - before.y * scale)
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        // Same as the workspace: scroll zooms at the cursor; Option-scroll pans, Shift-Option-scroll sideways.
        if event.modifierFlags.contains(.option) {
            if event.modifierFlags.contains(.shift) {
                offset.x += abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            } else {
                offset.y += event.scrollingDeltaY
            }
            needsDisplay = true
        } else {
            zoom(by: exp(event.scrollingDeltaY * 0.01), about: convert(event.locationInWindow, from: nil))
        }
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification, about: convert(event.locationInWindow, from: nil))
    }
}

// MARK: - Window

final class AlignToDisplayController: NSObject, NSWindowDelegate {
    private enum Mode: Int { case corners, measure }

    let window: NSWindow
    /// Called with the frame to give the image when Match is pressed.
    var onMatch: ((ImageFrame) -> Void)?
    var onClose: (() -> Void)?

    private let canvas = AlignCanvasView()
    private let modeControl = NSSegmentedControl(labels: ["Four Corners", "Set Measurement"], trackingMode: .selectOne, target: nil, action: nil)
    private let displayMenu = NSPopUpButton(title: "", target: nil, action: nil)
    private let lengthInput = NumberInput()
    private let instruction = NSTextField(labelWithString: "")
    private let matchButton = NSButton(title: "Match", target: nil, action: nil)
    private var displayControls: NSView!
    private var measureControls: NSView!

    private let image: NSImage
    private let targets: [AlignTarget]
    private let current: ImageFrame

    init(image: NSImage, targets: [AlignTarget], preselect: CGDirectDisplayID?, current: ImageFrame) {
        self.image = image
        self.targets = targets
        self.current = current
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 720), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Align Reference Image to Display"
        window.minSize = NSSize(width: 760, height: 520)
        window.delegate = self
        window.isReleasedWhenClosed = false
        build(preselect: preselect)
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Layout

    private func build(preselect: CGDirectDisplayID?) {
        canvas.image = image
        canvas.onPointsChanged = { [weak self] in self?.updateState() }

        modeControl.selectedSegment = 0
        modeControl.target = self; modeControl.action = #selector(modeChanged)
        displayMenu.removeAllItems()
        for target in targets { displayMenu.addItem(withTitle: "\(target.label) – \(target.name)") }
        if let preselect, let index = targets.firstIndex(where: { $0.id == preselect }) { displayMenu.selectItem(at: index) }
        displayMenu.target = self; displayMenu.action = #selector(displayChanged)

        lengthInput.minimum = 0.01
        lengthInput.step = 0.1
        lengthInput.onChange = { [weak self] _ in self?.updateState() }
        lengthInput.widthAnchor.constraint(equalToConstant: 100).isActive = true

        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: 12)
            return field
        }
        let displayRow = NSStackView(views: [label("Display:"), displayMenu])
        displayRow.spacing = 8
        displayRow.alignment = .centerY
        displayControls = displayRow
        // How long the line you mark really is.
        let measureRow = NSStackView(views: [label("The line is"), lengthInput, label(MeasurementFormat.unitName + " long")])
        measureRow.spacing = 8
        measureRow.alignment = .centerY
        measureControls = measureRow
        measureControls.isHidden = true

        let top = NSStackView(views: [modeControl, displayControls, measureControls, NSView()])
        top.spacing = 14
        top.alignment = .centerY
        top.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        instruction.font = .systemFont(ofSize: 12)
        instruction.textColor = .secondaryLabelColor
        instruction.lineBreakMode = .byTruncatingTail
        instruction.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let undoButton = NSButton(title: "Undo Point", target: self, action: #selector(undoPoint))
        let clearButton = NSButton(title: "Clear Points", target: self, action: #selector(clearPoints))
        let fitButton = NSButton(title: "Fit Photo", target: self, action: #selector(fitPhoto))
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        matchButton.target = self; matchButton.action = #selector(match)
        matchButton.keyEquivalent = "\r"
        for button in [undoButton, clearButton, fitButton, cancelButton, matchButton] { button.bezelStyle = .rounded }
        let bottom = NSStackView(views: [instruction, NSView(), undoButton, clearButton, fitButton, cancelButton, matchButton])
        bottom.spacing = 8
        bottom.alignment = .centerY
        bottom.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        let content = NSView()
        for view in [top, canvas, bottom] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: content.topAnchor),
            top.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: top.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottom.topAnchor),
            bottom.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        window.contentView = content
        updateState()
    }

    // MARK: State

    private var mode: Mode { Mode(rawValue: modeControl.selectedSegment) ?? .corners }

    private var selectedTarget: AlignTarget? {
        targets.indices.contains(displayMenu.indexOfSelectedItem) ? targets[displayMenu.indexOfSelectedItem] : nil
    }

    @objc private func modeChanged() {
        canvas.clearPoints()
        canvas.maxPoints = mode == .corners ? 4 : 2
        canvas.marksCorners = mode == .corners
        displayControls.isHidden = mode != .corners
        measureControls.isHidden = mode != .measure
        matchButton.title = mode == .corners ? "Match" : "Apply Scale"
        updateState()
    }

    @objc private func displayChanged() { updateState() }

    private func updateState() {
        let marked = canvas.points.count
        switch mode {
        case .corners:
            instruction.stringValue = marked < 4
                ? "Click the four corners of the display in the photo, in any order (\(marked) of 4)."
                : "Drag any point to adjust it, then press Match to scale, turn and place the image on the display."
            matchButton.isEnabled = marked == 4 && selectedTarget != nil
        case .measure:
            switch marked {
            case 0: instruction.stringValue = "Click one end of something in the photo whose real length you know."
            case 1: instruction.stringValue = "Click the other end."
            default: instruction.stringValue = "Drag the ends to adjust, enter the real length, then press Apply Scale. The image keeps its position."
            }
            matchButton.isEnabled = marked == 2 && lengthInput.value > 0
        }
    }

    // MARK: Actions

    @objc private func undoPoint() { canvas.removeLastPoint() }
    @objc private func clearPoints() { canvas.clearPoints() }
    @objc private func fitPhoto() { canvas.fit() }
    @objc private func cancel() { window.close() }

    @objc private func match() {
        let frame: ImageFrame?
        switch mode {
        case .corners:
            guard let rect = selectedTarget?.rect, let order = ReferenceAlignment.cornerOrder(of: canvas.points) else { return }
            // Top-left, top-right, bottom-right, bottom-left, with the workspace's y pointing up.
            let corners = [CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.minY)]
            frame = ReferenceAlignment.fitPoints(imagePoints: order.map { canvas.points[$0] }, imageSize: image.size, targets: corners)
        case .measure:
            guard canvas.points.count == 2 else { return }
            frame = ReferenceAlignment.scaled(toMeasure: canvas.points[0], canvas.points[1], imageSize: image.size, length: lengthInput.value, current: current)
        }
        guard let frame else { NSSound.beep(); return }
        onMatch?(frame)
        window.close()
    }

    func windowWillClose(_ notification: Notification) { onClose?() }
}
