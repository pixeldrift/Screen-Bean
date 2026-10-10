//
//  DisplayInspectorView.swift
//  ScreenBean
//

import Cocoa

/// Numeric text field that also supports click-and-drag value scrubbing.
final class ScrubbableNumberField: NSTextField {
    var scrubScale: Double = 0.1
    private var scrubStartX: CGFloat = 0
    private var scrubStartY: CGFloat = 0
    private var scrubStartValue: Double = 0
    private var scrubbing = false

    override func mouseDown(with event: NSEvent) {
        if event.clickCount > 1 || window == nil {
            super.mouseDown(with: event)
            return
        }
        let local = convert(event.locationInWindow, from: nil)
        let inRightScrubZone = local.x > bounds.width - 12
        if inRightScrubZone {
            scrubStartX = event.locationInWindow.x
            scrubStartY = event.locationInWindow.y
            scrubStartValue = doubleValue
            scrubbing = true
            window?.makeFirstResponder(self)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard scrubbing else { super.mouseDragged(with: event); return }
        let delta = Double(event.locationInWindow.x - scrubStartX) - Double(event.locationInWindow.y - scrubStartY)
        doubleValue = max(0, scrubStartValue + delta * scrubScale)
        currentEditor()?.string = stringValue
        sendAction(action, to: target)
    }

    override func mouseUp(with event: NSEvent) {
        if scrubbing { scrubbing = false; return }
        super.mouseUp(with: event)
    }

    private func currentEditor() -> NSTextView? {
        currentEditor() as? NSTextView
    }
}

final class DisplayInspectorView: NSView {
    var onChange: ((String?, Double?, Double?, Double?, Double?, NSColor?, Bool?, Double?, Double?, Double?, Double?) -> Void)?

    private let nicknameField = NSTextField(string: "")
    private let detectedName = NSTextField(labelWithString: "")
    private let widthField = ScrubbableNumberField(string: "")
    private let heightField = ScrubbableNumberField(string: "")
    private let xField = ScrubbableNumberField(string: "")
    private let yField = ScrubbableNumberField(string: "")
    private let colorWell = NSColorWell()
    private let uniformCheck = NSButton(checkboxWithTitle: "Uniform bezel", target: nil, action: nil)
    private let uniformField = ScrubbableNumberField(string: "")
    private let uniformSlider = NSSlider(value: 0.25, minValue: 0, maxValue: 2, target: nil, action: nil)
    private let topField = ScrubbableNumberField(string: "")
    private let bottomField = ScrubbableNumberField(string: "")
    private let leftField = ScrubbableNumberField(string: "")
    private let rightField = ScrubbableNumberField(string: "")
    private let resolutionValue = NSTextField(labelWithString: "—")
    private let ppiValue = NSTextField(labelWithString: "—")
    private let roleValue = NSTextField(labelWithString: "—")
    private var currentDisplay: DisplayInfo?
    private var currentX: Double = 0
    private var currentY: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }

    required init?(coder: NSCoder) { super.init(coder: coder); buildUI() }

    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let title = NSTextField(labelWithString: "Display Inspector")
        title.font = .boldSystemFont(ofSize: 16)
        detectedName.font = .systemFont(ofSize: 11)
        detectedName.textColor = .secondaryLabelColor
        detectedName.lineBreakMode = .byTruncatingTail

        nicknameField.placeholderString = "Custom monitor name"
        nicknameField.target = self; nicknameField.action = #selector(nicknameChanged)

        for field in [widthField, heightField, xField, yField, uniformField, topField, bottomField, leftField, rightField] {
            field.isEditable = true
            field.isBezeled = true
            field.bezelStyle = .roundedBezel
            field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            field.formatter = NumberFormatter()
            (field.formatter as? NumberFormatter)?.numberStyle = .decimal
            (field.formatter as? NumberFormatter)?.maximumFractionDigits = 2
            field.target = self
            field.action = #selector(numberChanged(_:))
            field.scrubScale = 0.05
        }
        widthField.scrubScale = 0.1; heightField.scrubScale = 0.1
        xField.scrubScale = 0.1; yField.scrubScale = 0.1
        uniformField.scrubScale = 0.01
        for field in [topField, bottomField, leftField, rightField] { field.scrubScale = 0.01 }

        uniformCheck.target = self; uniformCheck.action = #selector(uniformChanged)
        colorWell.target = self; colorWell.action = #selector(colorChanged)
        uniformSlider.target = self; uniformSlider.action = #selector(sliderChanged)

        let sizeRow = horizontalRow(label: "Width (in)", control: widthField, secondLabel: "Height", secondControl: heightField)
        let positionRow = horizontalRow(label: "X (in)", control: xField, secondLabel: "Y", secondControl: yField)
        let bezelUniformRow = horizontalRow(label: "Bezel (in)", control: uniformField, secondLabel: "", secondControl: NSView())
        let individualRow1 = horizontalRow(label: "Top", control: topField, secondLabel: "Bottom", secondControl: bottomField)
        let individualRow2 = horizontalRow(label: "Left", control: leftField, secondLabel: "Right", secondControl: rightField)

        let stack = NSStackView(views: [
            title, nicknameField, detectedName,
            sectionLabel("Dimensions"), sizeRow,
            sectionLabel("Position"), positionRow,
            sectionLabel("Appearance"), horizontalRow(label: "Body color", control: colorWell),
            uniformCheck, bezelUniformRow, uniformSlider, individualRow1, individualRow2,
            NSBox(), sectionLabel("Detected"), labeledValue("Resolution", resolutionValue),
            labeledValue("Pixel density", ppiValue), labeledValue("Display role", roleValue)
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18)
        ])
        widthField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        heightField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        xField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        yField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        uniformField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        colorWell.widthAnchor.constraint(equalToConstant: 58).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 28).isActive = true
        uniformSlider.widthAnchor.constraint(equalToConstant: 210).isActive = true
        refresh(nil, x: 0, y: 0)
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text.uppercased())
        field.font = .boldSystemFont(ofSize: 10)
        field.textColor = .secondaryLabelColor
        return field
    }

    private func labeledValue(_ label: String, _ value: NSTextField) -> NSView {
        let caption = NSTextField(labelWithString: label)
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        let row = NSStackView(views: [caption, value])
        row.orientation = .vertical; row.alignment = .leading; row.spacing = 2
        return row
    }

    private func horizontalRow(label: String, control: NSView, secondLabel: String? = nil, secondControl: NSView? = nil) -> NSView {
        let first = NSTextField(labelWithString: label)
        first.font = .systemFont(ofSize: 11)
        first.widthAnchor.constraint(equalToConstant: 66).isActive = true
        var views: [NSView] = [first, control]
        if let secondLabel, !secondLabel.isEmpty, let secondControl {
            let second = NSTextField(labelWithString: secondLabel)
            second.font = .systemFont(ofSize: 11)
            second.widthAnchor.constraint(equalToConstant: 48).isActive = true
            views += [second, secondControl]
        }
        let row = NSStackView(views: views)
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 5
        return row
    }

    func refresh(_ display: DisplayInfo?, x: CGFloat, y: CGFloat) {
        currentDisplay = display; currentX = Double(x); currentY = Double(y)
        guard let display else {
            nicknameField.stringValue = ""; detectedName.stringValue = "Select a monitor to edit its properties"
            for f in [widthField, heightField, xField, yField, uniformField, topField, bottomField, leftField, rightField] { f.stringValue = ""; f.isEnabled = false }
            colorWell.isEnabled = false; uniformCheck.isEnabled = false; uniformSlider.isEnabled = false
            resolutionValue.stringValue = "—"; ppiValue.stringValue = "—"; roleValue.stringValue = "—"
            return
        }
        nicknameField.stringValue = display.nickname
        detectedName.stringValue = "Detected: " + DisplayInfo.displayName(for: display.displayID)
        widthField.stringValue = String(format: "%.2f", display.physicalWidthInches)
        heightField.stringValue = String(format: "%.2f", display.physicalHeightInches)
        xField.stringValue = String(format: "%.2f", x); yField.stringValue = String(format: "%.2f", y)
        colorWell.color = Self.color(fromHex: display.colorHex)
        uniformCheck.state = display.uniformBezel ? .on : .off
        let average = display.uniformBezel ? display.bezelTop : (display.bezelTop + display.bezelBottom + display.bezelLeft + display.bezelRight) / 4
        uniformField.stringValue = String(format: "%.2f", average)
        uniformSlider.doubleValue = average
        topField.stringValue = String(format: "%.2f", display.bezelTop)
        bottomField.stringValue = String(format: "%.2f", display.bezelBottom)
        leftField.stringValue = String(format: "%.2f", display.bezelLeft)
        rightField.stringValue = String(format: "%.2f", display.bezelRight)
        for f in [widthField, heightField, xField, yField, uniformField, topField, bottomField, leftField, rightField] { f.isEnabled = true }
        colorWell.isEnabled = true; uniformCheck.isEnabled = true; uniformSlider.isEnabled = display.uniformBezel
        uniformField.isHidden = !display.uniformBezel; uniformSlider.isHidden = !display.uniformBezel
        topField.superview?.isHidden = display.uniformBezel
        bottomField.superview?.isHidden = display.uniformBezel
        leftField.superview?.isHidden = display.uniformBezel
        rightField.superview?.isHidden = display.uniformBezel
        resolutionValue.stringValue = "\(display.pixelWidth) × \(display.pixelHeight) pixels"
        ppiValue.stringValue = String(format: "%.0f PPI", display.ppi)
        roleValue.stringValue = display.isPrimary ? "Primary display" : "Secondary display"
    }

    @objc private func nicknameChanged() { emit(nickname: nicknameField.stringValue) }
    @objc private func numberChanged(_ sender: Any?) {
        if let sender = sender as? NSTextField {
            if sender === widthField { emit(width: widthField.doubleValue) }
            else if sender === heightField { emit(height: heightField.doubleValue) }
            else if sender === xField { emit(x: xField.doubleValue) }
            else if sender === yField { emit(y: yField.doubleValue) }
            else if sender === uniformField { applyUniform(uniformField.doubleValue) }
            else if sender === topField { emit(bezelTop: topField.doubleValue) }
            else if sender === bottomField { emit(bezelBottom: bottomField.doubleValue) }
            else if sender === leftField { emit(bezelLeft: leftField.doubleValue) }
            else if sender === rightField { emit(bezelRight: rightField.doubleValue) }
        }
    }
    @objc private func uniformChanged() {
        let isUniform = uniformCheck.state == .on
        emit(uniform: isUniform)
        refresh(currentDisplay, x: currentX, y: currentY)
    }
    @objc private func sliderChanged() { applyUniform(uniformSlider.doubleValue) }
    @objc private func colorChanged() { emit(color: colorWell.color) }

    private func applyUniform(_ value: Double) {
        uniformField.doubleValue = value
        emit(uniform: true, top: value, bottom: value, left: value, right: value)
    }

    private func emit(nickname: String? = nil, width: Double? = nil, height: Double? = nil, x: Double? = nil, y: Double? = nil, color: NSColor? = nil, uniform: Bool? = nil, top: Double? = nil, bottom: Double? = nil, left: Double? = nil, right: Double? = nil) {
        onChange?(nickname, width, height, x, y, color, uniform, top, bottom, left, right)
    }

    private static func color(fromHex hex: String) -> NSColor {
        let v = UInt64(hex, radix: 16) ?? 0x28B7B0
        return NSColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
}
