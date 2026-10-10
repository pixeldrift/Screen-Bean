import Cocoa

final class ScrubbableNumberField: NSTextField {
    var scrubScale: Double = 0.05
    var minimumValue: Double = 0
    private var start = CGPoint.zero
    private var startValue = 0.0
    private var scrubbing = false

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.x >= bounds.width - 14 {
            start = event.locationInWindow
            startValue = doubleValue
            scrubbing = true
            window?.makeFirstResponder(self)
        } else {
            super.mouseDown(with: event)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard scrubbing else { super.mouseDragged(with: event); return }
        let delta = Double(event.locationInWindow.x - start.x) - Double(event.locationInWindow.y - start.y)
        doubleValue = max(minimumValue, startValue + delta * scrubScale)
        sendAction(action, to: target)
    }
    override func mouseUp(with event: NSEvent) {
        if scrubbing { scrubbing = false } else { super.mouseUp(with: event) }
    }
}

final class DisplayInspectorView: NSView {
    var onChange: ((String?, Double?, Double?, Double?, Double?, NSColor?, Bool?, Double?, Double?, Double?, Double?) -> Void)?
    private let nickname = NSTextField(string: "")
    private let detected = NSTextField(labelWithString: "")
    private let width = ScrubbableNumberField(string: "")
    private let height = ScrubbableNumberField(string: "")
    private let x = ScrubbableNumberField(string: "")
    private let y = ScrubbableNumberField(string: "")
    private let color = NSColorWell(frame: .zero)
    private let uniform = NSButton(checkboxWithTitle: "Uniform bezel", target: nil, action: nil)
    private let bezel = ScrubbableNumberField(string: "")
    private let slider = NSSlider(value: 0.25, minValue: 0, maxValue: 2, target: nil, action: nil)
    private let top = ScrubbableNumberField(string: "")
    private let bottom = ScrubbableNumberField(string: "")
    private let left = ScrubbableNumberField(string: "")
    private let right = ScrubbableNumberField(string: "")
    private let resolution = NSTextField(labelWithString: "—")
    private let ppi = NSTextField(labelWithString: "—")
    private let role = NSTextField(labelWithString: "—")
    private var display: DisplayInfo?
    private var px = 0.0
    private var py = 0.0

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let title = NSTextField(labelWithString: "Display Inspector")
        title.font = .boldSystemFont(ofSize: 16)
        detected.font = .systemFont(ofSize: 11)
        detected.textColor = .secondaryLabelColor
        nickname.placeholderString = "Custom monitor name"
        nickname.target = self; nickname.action = #selector(nameChanged)
        for f in [width, height, x, y, bezel, top, bottom, left, right] {
            f.isEditable = true; f.isBezeled = true; f.bezelStyle = .roundedBezel
            f.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            let n = NumberFormatter(); n.numberStyle = .decimal; n.maximumFractionDigits = 2
            f.formatter = n; f.target = self; f.action = #selector(numberChanged(_:))
            f.scrubScale = 0.05
            f.widthAnchor.constraint(equalToConstant: 68).isActive = true
        }
        width.scrubScale = 0.1; height.scrubScale = 0.1; x.scrubScale = 0.1; y.scrubScale = 0.1
        x.minimumValue = -100000; y.minimumValue = -100000
        uniform.target = self; uniform.action = #selector(uniformChanged)
        color.target = self; color.action = #selector(colorChanged)
        slider.target = self; slider.action = #selector(sliderChanged)
        let r1 = row("Width", width, "Height", height)
        let r2 = row("X (in)", x, "Y (in)", y)
        let r3 = row("Bezel", bezel)
        let r4 = row("Top", top, "Bottom", bottom)
        let r5 = row("Left", left, "Right", right)
        let colorRow = row("Body color", color)
        let stack = NSStackView(views: [title, nickname, detected, heading("DIMENSIONS"), r1, heading("POSITION"), r2, heading("APPEARANCE"), colorRow, uniform, r3, slider, r4, r5, heading("DETECTED"), valueRow("Resolution", resolution), valueRow("Pixel density", ppi), valueRow("Display role", role)])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14), stack.topAnchor.constraint(equalTo: topAnchor, constant: 18)])
        slider.widthAnchor.constraint(equalToConstant: 210).isActive = true
        color.widthAnchor.constraint(equalToConstant: 60).isActive = true
        color.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }
    private func heading(_ s: String) -> NSTextField { let f = NSTextField(labelWithString: s); f.font = .boldSystemFont(ofSize: 10); f.textColor = .secondaryLabelColor; return f }
    private func row(_ l1: String, _ c1: NSView, _ l2: String? = nil, _ c2: NSView? = nil) -> NSView {
        let a = NSTextField(labelWithString: l1); a.font = .systemFont(ofSize: 11); a.widthAnchor.constraint(equalToConstant: 58).isActive = true
        var v: [NSView] = [a, c1]
        if let l2, let c2 { let b = NSTextField(labelWithString: l2); b.font = .systemFont(ofSize: 11); b.widthAnchor.constraint(equalToConstant: 44).isActive = true; v += [b, c2] }
        let s = NSStackView(views: v); s.orientation = .horizontal; s.alignment = .centerY; s.spacing = 4; return s
    }
    private func valueRow(_ label: String, _ value: NSTextField) -> NSView { let s = NSStackView(views: [heading(label), value]); s.orientation = .vertical; s.alignment = .leading; s.spacing = 2; return s }

    func refresh(_ d: DisplayInfo?, x: CGFloat, y: CGFloat) {
        display = d; px = Double(x); py = Double(y)
        guard let d else {
            nickname.stringValue = ""; detected.stringValue = "Select a monitor to edit properties"
            for f in [width, height, self.x, self.y, bezel, top, bottom, left, right] { f.stringValue = ""; f.isEnabled = false }
            color.isEnabled = false; uniform.isEnabled = false; slider.isEnabled = false
            resolution.stringValue = "—"; ppi.stringValue = "—"; role.stringValue = "—"
            return
        }
        nickname.stringValue = d.nickname; detected.stringValue = "Detected: " + DisplayInfo.displayName(for: d.displayID)
        width.stringValue = String(format: "%.2f", d.physicalWidthInches); height.stringValue = String(format: "%.2f", d.physicalHeightInches)
        self.x.stringValue = String(format: "%.2f", x); self.y.stringValue = String(format: "%.2f", y)
        color.color = colorFromHex(d.colorHex); uniform.state = d.uniformBezel ? .on : .off
        let b = d.uniformBezel ? d.bezelTop : (d.bezelTop + d.bezelBottom + d.bezelLeft + d.bezelRight) / 4
        bezel.stringValue = String(format: "%.2f", b); slider.doubleValue = b
        top.stringValue = String(format: "%.2f", d.bezelTop); bottom.stringValue = String(format: "%.2f", d.bezelBottom)
        left.stringValue = String(format: "%.2f", d.bezelLeft); right.stringValue = String(format: "%.2f", d.bezelRight)
        for f in [width, height, self.x, self.y, bezel, top, bottom, left, right] { f.isEnabled = true }
        color.isEnabled = true; uniform.isEnabled = true; slider.isEnabled = d.uniformBezel
        bezel.superview?.isHidden = !d.uniformBezel; slider.isHidden = !d.uniformBezel
        top.superview?.isHidden = d.uniformBezel; left.superview?.isHidden = d.uniformBezel
        resolution.stringValue = "\(d.pixelWidth) × \(d.pixelHeight) pixels"; ppi.stringValue = String(format: "%.0f PPI", d.ppi)
        role.stringValue = d.isPrimary ? "Primary display" : "Secondary display"
    }
    @objc private func nameChanged() { emit(name: nickname.stringValue) }
    @objc private func numberChanged(_ sender: NSTextField) {
        if sender === width { emit(w: width.doubleValue) }
        else if sender === height { emit(h: height.doubleValue) }
        else if sender === x { emit(x: x.doubleValue) }
        else if sender === y { emit(y: y.doubleValue) }
        else if sender === bezel { uniformBezelValue(bezel.doubleValue) }
        else if sender === top { emit(t: top.doubleValue) }
        else if sender === bottom { emit(b: bottom.doubleValue) }
        else if sender === left { emit(l: left.doubleValue) }
        else if sender === right { emit(r: right.doubleValue) }
    }
    @objc private func uniformChanged() { emit(uniform: uniform.state == .on) }
    @objc private func sliderChanged() { uniformBezelValue(slider.doubleValue) }
    @objc private func colorChanged() { emit(color: color.color) }
    private func uniformBezelValue(_ v: Double) { bezel.doubleValue = v; emit(uniform: true, t: v, b: v, l: v, r: v) }
    private func emit(name: String? = nil, w: Double? = nil, h: Double? = nil, x: Double? = nil, y: Double? = nil, color: NSColor? = nil, uniform: Bool? = nil, t: Double? = nil, b: Double? = nil, l: Double? = nil, r: Double? = nil) {
        onChange?(name, w, h, x, y, color, uniform, t, b, l, r)
    }
    private func colorFromHex(_ hex: String) -> NSColor {
        let v = UInt64(hex, radix: 16) ?? 0x28B7B0
        return NSColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
}
