import Cocoa

/// Document view for the inspector's scroll view; top-left origin so content starts at the top.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class DisplayInspectorView: NSView {
    var onChange: ((DisplayEdit) -> Void)?

    private let nickname = NSTextField(string: "")
    private let detected = NSTextField(labelWithString: "")
    private let lockButton = NSButton()
    private let width = NumberInput()
    private let height = NumberInput()
    private let x = NumberInput()
    private let y = NumberInput()
    private let uniform = NSButton(checkboxWithTitle: "Uniform", target: nil, action: nil)
    private let bezel = NumberInput()
    private let slider = NSSlider(value: DisplayDefaults.bezelInches, minValue: 0, maxValue: 2, target: nil, action: nil)
    private let top = NumberInput()
    private let bottom = NumberInput()
    private let left = NumberInput()
    private let right = NumberInput()
    private let swatch = NSBox()
    private let picker = ColorPickerView()
    private let showBezel = NSButton(checkboxWithTitle: "Show bezel", target: nil, action: nil)
    private let resolution = NSTextField(labelWithString: "—")
    private let ppi = NSTextField(labelWithString: "—")
    private let role = NSTextField(labelWithString: "—")
    private var isLocked = false
    private var hasDisplay = false
    private var uniformSection: NSView!
    private var individualSection: NSView!

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    // MARK: - Layout

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        // Header: title and lock toggle.
        let title = NSTextField(labelWithString: "Display Properties")
        title.font = .boldSystemFont(ofSize: 16)
        lockButton.isBordered = false
        lockButton.target = self; lockButton.action = #selector(lockToggled)
        lockButton.imageScaling = .scaleProportionallyUpOrDown
        lockButton.widthAnchor.constraint(equalToConstant: 20).isActive = true
        lockButton.heightAnchor.constraint(equalToConstant: 20).isActive = true
        let header = NSStackView(views: [title, NSView(), lockButton])
        header.distribution = .fill

        nickname.placeholderString = "Custom monitor name"
        nickname.target = self; nickname.action = #selector(nameChanged)
        detected.font = .systemFont(ofSize: 11); detected.textColor = .secondaryLabelColor

        // Inputs.
        for input in [width, height, x, y] { input.step = 0.1 }
        width.minimum = 0.1; height.minimum = 0.1
        x.minimum = -100000; y.minimum = -100000
        for input in [bezel, top, bottom, left, right] { input.step = 0.05 }
        width.onChange = { [weak self] in self?.emit(DisplayEdit(width: $0)) }
        height.onChange = { [weak self] in self?.emit(DisplayEdit(height: $0)) }
        x.onChange = { [weak self] in self?.emit(DisplayEdit(x: $0)) }
        y.onChange = { [weak self] in self?.emit(DisplayEdit(y: $0)) }
        bezel.onChange = { [weak self] in self?.setUniformBezel($0) }
        top.onChange = { [weak self] in self?.emit(DisplayEdit(bezelTop: $0)) }
        bottom.onChange = { [weak self] in self?.emit(DisplayEdit(bezelBottom: $0)) }
        left.onChange = { [weak self] in self?.emit(DisplayEdit(bezelLeft: $0)) }
        right.onChange = { [weak self] in self?.emit(DisplayEdit(bezelRight: $0)) }
        uniform.target = self; uniform.action = #selector(uniformChanged)
        slider.target = self; slider.action = #selector(sliderChanged)
        showBezel.target = self; showBezel.action = #selector(showBezelChanged)
        picker.onChange = { [weak self] color in self?.swatch.fillColor = color; self?.emit(DisplayEdit(color: color)) }
        swatch.boxType = .custom; swatch.cornerRadius = 4; swatch.borderWidth = 1
        swatch.borderColor = .separatorColor; swatch.titlePosition = .noTitle
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.widthAnchor.constraint(equalToConstant: 56).isActive = true
        swatch.heightAnchor.constraint(equalToConstant: 22).isActive = true

        // Sections.
        let dimensions = section("Dimensions & Position", [
            grid(cell("Width", "inches", width), cell("Height", "inches", height)),
            grid(cell("X-Pos", "inches", x), cell("Y-Pos", "inches", y))
        ])
        uniformSection = stack([cell("Bezel Size", "inches", bezel), slider], spacing: 6)
        individualSection = stack([
            caption("Individual Bezel Sizes", "inches"),
            grid(cell("Top", nil, top), cell("Bottom", nil, bottom)),
            grid(cell("Left", nil, left), cell("Right", nil, right))
        ], spacing: 6)
        let bezelHeader = NSStackView(views: [sectionTitle("Bezel"), NSView(), uniform])
        bezelHeader.distribution = .fill
        let bezelSection = stack([bezelHeader, uniformSection, individualSection], spacing: 8)
        let colorRow = NSStackView(views: [NSTextField(labelWithString: "Display Color"), swatch])
        colorRow.spacing = 8
        let appearance = stack([sectionTitle("Appearance"), colorRow, picker], spacing: 8)
        let frameSection = section("Monitor Frame", [showBezel])
        let info = section("Detected", [valueRow("Resolution", resolution), valueRow("Pixel density", ppi), valueRow("Display role", role)])

        let content = stack([header, stack([nickname, detected], spacing: 4), divider(), dimensions, divider(), bezelSection, divider(), appearance, divider(), frameSection, divider(), info], spacing: 12)
        content.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -18)
        ])
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        updateLockButton()
    }

    // MARK: - Layout helpers

    private func stack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical; s.alignment = .width; s.spacing = spacing
        return s
    }
    private func section(_ title: String, _ views: [NSView]) -> NSStackView { stack([sectionTitle(title)] + views, spacing: 8) }
    private func sectionTitle(_ s: String) -> NSTextField { let f = NSTextField(labelWithString: s); f.font = .boldSystemFont(ofSize: 13); return f }
    private func caption(_ text: String, _ unit: String) -> NSTextField {
        let f = NSTextField(labelWithString: "")
        let a = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11)])
        a.append(NSAttributedString(string: " (\(unit))", attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]))
        f.attributedStringValue = a
        return f
    }
    private func divider() -> NSBox { let b = NSBox(); b.boxType = .separator; return b }
    /// A scrubbable caption above a number input.
    private func cell(_ label: String, _ unit: String?, _ input: NumberInput) -> NSView {
        let l = ScrubLabel(label, unit: unit, input: input)
        return stack([l, input], spacing: 4)
    }
    private func grid(_ a: NSView, _ b: NSView) -> NSStackView {
        let s = NSStackView(views: [a, b])
        s.distribution = .fillEqually; s.spacing = 16; s.alignment = .top
        return s
    }
    private func valueRow(_ label: String, _ value: NSTextField) -> NSView {
        let l = NSTextField(labelWithString: label); l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor
        value.font = .systemFont(ofSize: 12)
        return stack([l, value], spacing: 2)
    }

    // MARK: - State

    func refresh(_ d: DisplayInfo?, x px: CGFloat, y py: CGFloat) {
        guard let d else {
            hasDisplay = false
            nickname.stringValue = ""; detected.stringValue = "Select a monitor to edit properties"
            for input in [width, height, x, y, bezel, top, bottom, left, right] { input.clear() }
            resolution.stringValue = "—"; ppi.stringValue = "—"; role.stringValue = "—"
            isLocked = false
            updateLockButton(); applyEnabled()
            return
        }
        hasDisplay = true
        isLocked = d.isLocked
        if nickname.currentEditor() == nil { nickname.stringValue = d.nickname }
        detected.stringValue = "Detected: " + DisplayInfo.displayName(for: d.displayID)
        width.value = d.physicalWidthInches; height.value = d.physicalHeightInches
        x.value = Double(px); y.value = Double(py)
        uniform.state = d.uniformBezel ? .on : .off
        let b = d.uniformBezel ? d.bezelTop : (d.bezelTop + d.bezelBottom + d.bezelLeft + d.bezelRight) / 4
        bezel.value = b; slider.doubleValue = b
        top.value = d.bezelTop; bottom.value = d.bezelBottom
        left.value = d.bezelLeft; right.value = d.bezelRight
        uniformSection.isHidden = !d.uniformBezel; individualSection.isHidden = d.uniformBezel
        // Keep the picker's hue steady while the user drags inside it.
        if picker.color.displayHex != d.colorHex { picker.color = NSColor(displayHex: d.colorHex) }
        swatch.fillColor = NSColor(displayHex: d.colorHex)
        showBezel.state = d.showBezel ? .on : .off
        resolution.stringValue = "\(d.pixelWidth) × \(d.pixelHeight) pixels"; ppi.stringValue = String(format: "%.0f PPI", d.ppi)
        role.stringValue = d.isPrimary ? "Primary display" : "Secondary display"
        updateLockButton(); applyEnabled()
    }

    /// Everything except the lock is read-only while the display is locked or nothing is selected.
    private func applyEnabled() {
        let editable = hasDisplay && !isLocked
        for input in [width, height, x, y, bezel, top, bottom, left, right] { input.isEnabled = editable }
        nickname.isEnabled = editable; uniform.isEnabled = editable; slider.isEnabled = editable
        showBezel.isEnabled = editable; picker.isEnabled = editable
        lockButton.isEnabled = hasDisplay
    }

    private func updateLockButton() {
        let name = isLocked ? "lock.fill" : "lock.open"
        lockButton.image = NSImage(systemSymbolName: name, accessibilityDescription: isLocked ? "Unlock display" : "Lock display")
        lockButton.contentTintColor = isLocked ? .labelColor : .secondaryLabelColor
        lockButton.toolTip = isLocked ? "Locked – click to allow changes" : "Lock this display to prevent changes"
    }

    // MARK: - Actions

    private func emit(_ edit: DisplayEdit) { onChange?(edit) }
    @objc private func lockToggled() { emit(DisplayEdit(isLocked: !isLocked)) }
    @objc private func nameChanged() { emit(DisplayEdit(nickname: nickname.stringValue)) }
    @objc private func uniformChanged() { emit(DisplayEdit(uniformBezel: uniform.state == .on)) }
    @objc private func showBezelChanged() { emit(DisplayEdit(showBezel: showBezel.state == .on)) }
    @objc private func sliderChanged() { setUniformBezel(slider.doubleValue) }
    private func setUniformBezel(_ v: Double) {
        bezel.value = v; slider.doubleValue = v
        emit(DisplayEdit(uniformBezel: true, bezelTop: v, bezelBottom: v, bezelLeft: v, bezelRight: v))
    }
}
