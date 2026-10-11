//
//  ColorPickerView.swift
//  ScreenBean
//
//  An inline color picker: saturation/brightness square, hue strip, and
//  hex / RGB entry.
//

import Cocoa

final class ColorPickerView: NSView {
    var onChange: ((NSColor) -> Void)?
    var isEnabled = true {
        didSet { for f in [hexField, redField, greenField, blueField] { f.isEnabled = isEnabled }; needsDisplay = true }
    }

    private var hue: CGFloat = 0.5, saturation: CGFloat = 1, brightness: CGFloat = 1
    private let squareHeight: CGFloat = 130
    private let stripWidth: CGFloat = 20
    private let gap: CGFloat = 10
    private let fieldRowHeight: CGFloat = 26
    private let hexField = NSTextField(string: "")
    private let redField = NSTextField(string: "")
    private let greenField = NSTextField(string: "")
    private let blueField = NSTextField(string: "")
    private var dragTarget: Target?

    private enum Target { case square, strip }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: squareHeight + 10 + fieldRowHeight) }

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    var color: NSColor {
        get { NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1) }
        set {
            let c = newValue.usingColorSpace(.deviceRGB) ?? newValue
            hue = c.hueComponent; saturation = c.saturationComponent; brightness = c.brightnessComponent
            syncFields(); needsDisplay = true
        }
    }

    // Square and strip share the top of the view; fields sit underneath.
    private var squareRect: CGRect { CGRect(x: 0, y: bounds.height - squareHeight, width: max(bounds.width - stripWidth - gap, 1), height: squareHeight) }
    private var stripRect: CGRect { CGRect(x: bounds.width - stripWidth, y: bounds.height - squareHeight, width: stripWidth, height: squareHeight) }

    private func build() {
        let small = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        for f in [hexField, redField, greenField, blueField] {
            f.font = small; f.isBezeled = true; f.bezelStyle = .roundedBezel
            f.target = self; f.action = #selector(fieldChanged(_:))
            f.delegate = ReturnCommitDelegate.shared
        }
        let labels = ["R", "G", "B"].map { t -> NSTextField in
            let l = NSTextField(labelWithString: t); l.font = .systemFont(ofSize: 10); l.textColor = .secondaryLabelColor; return l
        }
        let row = NSStackView(views: [hexField, labels[0], redField, labels[1], greenField, labels[2], blueField])
        row.spacing = 3; row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        hexField.widthAnchor.constraint(equalToConstant: 76).isActive = true
        for f in [redField, greenField, blueField] { f.widthAnchor.constraint(equalToConstant: 38).isActive = true }
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        syncFields()
    }

    private func syncFields() {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        hexField.stringValue = "#" + color.displayHex
        redField.integerValue = Int((c.redComponent * 255).rounded())
        greenField.integerValue = Int((c.greenComponent * 255).rounded())
        blueField.integerValue = Int((c.blueComponent * 255).rounded())
    }

    @objc private func fieldChanged(_ sender: NSTextField) {
        if sender === hexField {
            let hex = hexField.stringValue.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            guard hex.count == 6, UInt64(hex, radix: 16) != nil else { syncFields(); return }
            color = NSColor(displayHex: hex)
        } else {
            func channel(_ f: NSTextField) -> CGFloat { CGFloat(min(max(f.integerValue, 0), 255)) / 255 }
            color = NSColor(deviceRed: channel(redField), green: channel(greenField), blue: channel(blueField), alpha: 1)
        }
        onChange?(color)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let alpha: CGFloat = isEnabled ? 1 : 0.4
        let sq = squareRect, strip = stripRect

        context.saveGState()
        context.setAlpha(alpha)
        // Saturation (left to right) over brightness (bottom to top).
        context.addPath(CGPath(roundedRect: sq, cornerWidth: 4, cornerHeight: 4, transform: nil)); context.clip()
        let space = CGColorSpaceCreateDeviceRGB()
        let hueColor = NSColor(hue: hue, saturation: 1, brightness: 1, alpha: 1).cgColor
        if let g = CGGradient(colorsSpace: space, colors: [NSColor.white.cgColor, hueColor] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(g, start: CGPoint(x: sq.minX, y: 0), end: CGPoint(x: sq.maxX, y: 0), options: [])
        }
        if let g = CGGradient(colorsSpace: space, colors: [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.cgColor] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(g, start: CGPoint(x: 0, y: sq.maxY), end: CGPoint(x: 0, y: sq.minY), options: [])
        }
        context.restoreGState()

        context.saveGState()
        context.setAlpha(alpha)
        context.addPath(CGPath(roundedRect: strip, cornerWidth: 4, cornerHeight: 4, transform: nil)); context.clip()
        let stops = stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { NSColor(hue: CGFloat(1 - $0), saturation: 1, brightness: 1, alpha: 1).cgColor }
        if let g = CGGradient(colorsSpace: space, colors: stops as CFArray, locations: stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { CGFloat($0) }) {
            context.drawLinearGradient(g, start: CGPoint(x: 0, y: strip.maxY), end: CGPoint(x: 0, y: strip.minY), options: [])
        }
        context.restoreGState()

        // Handles.
        let knob = CGPoint(x: sq.minX + saturation * sq.width, y: sq.minY + brightness * sq.height)
        context.setLineWidth(2); context.setStrokeColor(NSColor.white.cgColor)
        context.strokeEllipse(in: CGRect(x: knob.x - 6, y: knob.y - 6, width: 12, height: 12))
        let hueY = strip.minY + (1 - hue) * strip.height
        context.stroke(CGRect(x: strip.minX - 1, y: hueY - 2, width: strip.width + 2, height: 4))
    }

    // MARK: - Mouse
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let p = convert(event.locationInWindow, from: nil)
        if squareRect.contains(p) { dragTarget = .square }
        else if stripRect.insetBy(dx: -4, dy: 0).contains(p) { dragTarget = .strip }
        else { dragTarget = nil }
        update(at: p)
    }
    override func mouseDragged(with event: NSEvent) { update(at: convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) { dragTarget = nil }

    private func update(at p: CGPoint) {
        guard let dragTarget else { return }
        switch dragTarget {
        case .square:
            let r = squareRect
            saturation = min(max((p.x - r.minX) / r.width, 0), 1)
            brightness = min(max((p.y - r.minY) / r.height, 0), 1)
        case .strip:
            let r = stripRect
            hue = 1 - min(max((p.y - r.minY) / r.height, 0), 1)
        }
        syncFields(); needsDisplay = true
        onChange?(color)
    }
}

/// A color swatch that opens a `ColorPickerView` in a popover when clicked.
final class ColorSwatchButton: NSButton {
    var onChange: ((NSColor) -> Void)?
    private(set) var color: NSColor = .systemTeal
    private let picker = ColorPickerView()
    private let popover = NSPopover()

    override var isEnabled: Bool { didSet { needsDisplay = true } }

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        title = ""
        isBordered = false
        image = nil
        target = self; action = #selector(showPicker)
        setAccessibilityLabel("Choose color")
        picker.frame = NSRect(x: 0, y: 0, width: 260, height: 180)
        picker.onChange = { [weak self] color in
            self?.setColor(color)
            self?.onChange?(color)
        }
        let controller = NSViewController()
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 284, height: 204))
        picker.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 12),
            picker.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -12),
            picker.topAnchor.constraint(equalTo: holder.topAnchor, constant: 12),
            picker.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -12)
        ])
        controller.view = holder
        popover.contentViewController = controller
        popover.behavior = .transient
        widthAnchor.constraint(equalToConstant: 72).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    /// Updates the swatch (and the open picker) without notifying `onChange`.
    func setColor(_ newColor: NSColor) {
        color = newColor
        if picker.color.displayHex != newColor.displayHex { picker.color = newColor }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // The whole button is the swatch.
        let swatch = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: swatch, xRadius: 5, yRadius: 5)
        (isEnabled ? color : color.withAlphaComponent(0.5)).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    @objc private func showPicker() {
        guard isEnabled else { return }
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxX)
    }
}
