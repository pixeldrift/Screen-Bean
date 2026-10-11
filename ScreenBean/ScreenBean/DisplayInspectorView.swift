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
    private let displayColor = ColorSwatchButton()
    private let bezelColor = ColorSwatchButton()
    private let showBezel = NSButton(checkboxWithTitle: "Show bezel", target: nil, action: nil)
    private let resolution = NSTextField(labelWithString: "—")
    private let ppi = NSTextField(labelWithString: "—")
    private let role = NSTextField(labelWithString: "—")
    private var isLocked = false
    private var hasDisplay = false
    private var uniformSection: NSView!
    private var individualSection: NSView!
    private var showsBezel = true

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
        displayColor.onChange = { [weak self] in self?.emit(DisplayEdit(color: $0)) }
        bezelColor.onChange = { [weak self] in self?.emit(DisplayEdit(bezelColor: $0)) }
        detected.font = .systemFont(ofSize: 10)

        // Sections.
        let infoSection = stack([
            grid(valueCell("Native Resolution", resolution), valueCell("Pixel Density", ppi)),
            valueCell("Display Role", role)
        ], spacing: 8)
        let dimensions = section("Dimensions & Position", [
            grid(cell("Width", "inches", width), cell("Height", "inches", height)),
            grid(cell("X-Pos", "inches", x), cell("Y-Pos", "inches", y))
        ])

        // Bezel: size + uniform toggle, then either a slider or a cross of four sides.
        let sizeCell = cell("Bezel Size", "inches", bezel)
        sizeCell.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let sizeRow = NSStackView(views: [sizeCell, uniform])
        sizeRow.alignment = .bottom; sizeRow.spacing = 12
        uniformSection = slider
        let sideCells = [top, bottom, left, right].map { input -> NSView in
            let name = input === top ? "Top" : input === bottom ? "Bottom" : input === left ? "Left" : "Right"
            let c = cell(name, nil, input)
            c.widthAnchor.constraint(equalToConstant: 100).isActive = true
            return c
        }
        let middle = NSStackView(views: [sideCells[2], sideCells[3]])
        middle.spacing = 16
        let cross = NSStackView(views: [sideCells[0], middle, sideCells[1]])
        cross.orientation = .vertical; cross.alignment = .centerX; cross.spacing = 6
        individualSection = cross
        let bezelHeader = NSStackView(views: [sectionTitle("Bezel"), NSView(), showBezel])
        bezelHeader.distribution = .fill
        let bezelSection = stack([bezelHeader, sizeRow, uniformSection, individualSection, colorRow("Bezel Color", bezelColor)], spacing: 8)
        let appearance = section("Appearance", [colorRow("Display Color", displayColor)])

        let content = stack([header, stack([nickname, detected], spacing: 4), infoSection, divider(), dimensions, divider(), bezelSection, divider(), appearance], spacing: 12)
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
    private func cell(_ label: String, _ unit: String?, _ input: NumberInput) -> NSView { input.labeled(label, unit: unit) }
    private func grid(_ a: NSView, _ b: NSView) -> NSStackView { twoColumnGrid(a, b) }
    private func valueCell(_ label: String, _ value: NSTextField) -> NSView {
        let l = NSTextField(labelWithString: label); l.font = .systemFont(ofSize: 11)
        value.font = .systemFont(ofSize: 12); value.textColor = .secondaryLabelColor
        return stack([l, value], spacing: 2)
    }
    private func colorRow(_ label: String, _ button: ColorSwatchButton) -> NSView {
        let row = NSStackView(views: [NSTextField(labelWithString: label), button])
        row.spacing = 8
        return row
    }

    // MARK: - State

    func refresh(_ d: DisplayInfo?, x px: CGFloat, y py: CGFloat) {
        guard let d else {
            hasDisplay = false
            nickname.stringValue = ""; detected.stringValue = ""
            for input in [width, height, x, y, bezel, top, bottom, left, right] { input.clear() }
            resolution.stringValue = "—"; ppi.stringValue = "—"; role.stringValue = "—"
            isLocked = false
            updateLockButton(); applyEnabled()
            return
        }
        hasDisplay = true
        isLocked = d.isLocked
        if nickname.currentEditor() == nil { nickname.stringValue = d.nickname }
        detected.stringValue = "(" + DisplayInfo.displayName(for: d.displayID) + ")"
        width.value = d.physicalWidthInches; height.value = d.physicalHeightInches
        x.value = Double(px); y.value = Double(py)
        uniform.state = d.uniformBezel ? .on : .off
        let b = d.uniformBezel ? d.bezelTop : (d.bezelTop + d.bezelBottom + d.bezelLeft + d.bezelRight) / 4
        bezel.value = b; slider.doubleValue = b
        top.value = d.bezelTop; bottom.value = d.bezelBottom
        left.value = d.bezelLeft; right.value = d.bezelRight
        uniformSection.isHidden = !d.uniformBezel; individualSection.isHidden = d.uniformBezel
        displayColor.setColor(NSColor(displayHex: d.colorHex))
        bezelColor.setColor(NSColor(displayHex: d.bezelColorHex))
        showBezel.state = d.showBezel ? .on : .off
        showsBezel = d.showBezel
        resolution.stringValue = "\(d.pixelWidth) × \(d.pixelHeight) pixels"; ppi.stringValue = String(format: "%.0f PPI", d.ppi)
        role.stringValue = d.isPrimary ? "Primary display" : "Secondary display"
        updateLockButton(); applyEnabled()
    }

    /// Everything except the lock is read-only while the display is locked or nothing is selected.
    private func applyEnabled() {
        let editable = hasDisplay && !isLocked
        for input in [width, height, x, y] { input.isEnabled = editable }
        // The uniform field is read-only while individual sides are shown.
        let bezelEditable = editable && showsBezel
        for input in [top, bottom, left, right] { input.isEnabled = bezelEditable }
        bezel.isEnabled = bezelEditable && uniform.state == .on
        nickname.isEnabled = editable; showBezel.isEnabled = editable
        uniform.isEnabled = bezelEditable; slider.isEnabled = bezelEditable
        bezelColor.isEnabled = bezelEditable; displayColor.isEnabled = editable
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
