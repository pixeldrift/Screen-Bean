import Cocoa

/// Document view for the inspector's scroll view; top-left origin so content starts at the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Sizes the sidebar and its input columns share.
enum SidebarMetrics {
    static let width: CGFloat = 270
    static let inspectorInset: CGFloat = 16
    static let columnSpacing: CGFloat = 16
    /// Width of one of the two input columns, so every input box is the same size.
    static var columnWidth: CGFloat { (width - inspectorInset * 2 - columnSpacing) / 2 }
}

final class DisplayInspectorView: NSView {
    var onChange: ((DisplayEdit) -> Void)?
    /// Asks to move a virtual display's place and settings onto a connected display.
    var onAssignVirtual: ((CGDirectDisplayID) -> Void)?
    var onDeleteVirtual: (() -> Void)?
    /// The connected displays a virtual display could be assigned to.
    var connectedDisplays: [(id: CGDirectDisplayID, name: String)] = []

    private let nickname = NSTextField(string: "")
    private let detected = NSTextField(labelWithString: "")
    private let lockButton = NSButton()
    private let width = NumberInput()
    private let height = NumberInput()
    private let x = NumberInput()
    private let y = NumberInput()
    private let diagonal = NumberInput()
    private let aspectField = NSTextField(string: "")
    private let aspectLockButton = NSButton()
    private var aspectIsLocked = false
    private var shownAspect = ""
    private let detectedLabel = NSTextField(labelWithString: "")
    private let resetButton = NSButton(title: "Reset to Detected", target: nil, action: nil)
    private var detectedRow: NSView!
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
    private var sizeCaption: NSView!
    private let resolution = NSTextField(labelWithString: "—")
    private let ppi = NSTextField(labelWithString: "—")
    private let role = NSTextField(labelWithString: "—")
    private let orientation = NSTextField(labelWithString: "—")
    private let assignMenu = NSPopUpButton(title: "", target: nil, action: nil)
    private let deleteVirtualButton = NSButton(title: "Delete Virtual Display", target: nil, action: nil)
    private let keepCheckbox = NSButton(checkboxWithTitle: "Keep when disconnected", target: nil, action: nil)
    private var connectionSection: NSView!
    private let virtualNote = NSTextField(wrappingLabelWithString: "")
    private var virtualSection: NSView!
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
        nickname.delegate = ReturnCommitDelegate.shared
        detected.font = .systemFont(ofSize: 11); detected.textColor = .secondaryLabelColor

        // Inputs.
        for input in [width, height, x, y, diagonal] { input.step = 0.1 }
        diagonal.minimum = 0.1
        width.minimum = 0.1; height.minimum = 0.1
        x.minimum = -100000; y.minimum = -100000
        for input in [bezel, top, bottom, left, right] { input.step = 0.05 }
        width.onChange = { [weak self] in self?.emit(DisplayEdit(width: $0)) }
        height.onChange = { [weak self] in self?.emit(DisplayEdit(height: $0)) }
        diagonal.onChange = { [weak self] in self?.emit(DisplayEdit(diagonal: $0)) }
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
        // Long names must not widen the panel and push the name field off the edge.
        for label in [detected, resolution, ppi, role, orientation] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        nickname.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NotificationCenter.default.addObserver(forName: BezelVisibility.didChange, object: nil, queue: .main) { [weak self] _ in self?.applyEnabled() }

        // Sections.
        let infoSection = stack([
            grid(valueCell("Native Resolution", resolution), valueCell("Pixel Density", ppi)),
            grid(valueCell("Display Role", role), valueCell("Orientation", orientation))
        ], spacing: 8)
        // Aspect ratio: a text field ("16:9" or "1.78") and a lock that keeps the shape while sizes change.
        aspectField.placeholderString = "16:9"
        aspectField.target = self; aspectField.action = #selector(aspectEdited)
        aspectField.delegate = ReturnCommitDelegate.shared
        aspectField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        aspectLockButton.isBordered = false
        aspectLockButton.imageScaling = .scaleProportionallyUpOrDown
        aspectLockButton.target = self; aspectLockButton.action = #selector(aspectLockToggled)
        aspectLockButton.widthAnchor.constraint(equalToConstant: 14).isActive = true
        aspectLockButton.heightAnchor.constraint(equalToConstant: 14).isActive = true
        let aspectCaption = NSTextField(labelWithString: "Aspect Ratio")
        aspectCaption.font = .systemFont(ofSize: 11)
        let aspectHeader = NSStackView(views: [aspectCaption, aspectLockButton, NSView()])
        aspectHeader.spacing = 4
        aspectHeader.distribution = .fill
        let aspectCell = stack([aspectHeader, aspectField], spacing: 4)
        updateAspectLockButton()
        // What macOS reported, and a way back to it once the size has been changed.
        detectedLabel.font = .systemFont(ofSize: 10); detectedLabel.textColor = .secondaryLabelColor
        detectedLabel.lineBreakMode = .byTruncatingTail
        detectedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        resetButton.bezelStyle = .rounded; resetButton.controlSize = .small
        resetButton.target = self; resetButton.action = #selector(resetToDetected)
        let detectedStack = NSStackView(views: [detectedLabel, NSView(), resetButton])
        detectedStack.spacing = 6
        detectedStack.distribution = .fill
        detectedRow = detectedStack
        detectedRow.isHidden = true
        let dimensions = section("Dimensions & Position", [
            grid(cell("Width", "inches", width), cell("Height", "inches", height)),
            grid(cell("Diagonal", "inches", diagonal), aspectCell),
            detectedRow,
            grid(cell("X-Pos", "inches", x), cell("Y-Pos", "inches", y))
        ])

        // Bezel: a size caption with the Uniform toggle, then either one field and a slider
        // or a cross of four sides, then colors and visibility.
        let caption = ScrubLabel("Bezel Size", unit: "inches", input: bezel)
        sizeCaption = caption
        let sizeHeader = NSStackView(views: [caption, NSView(), uniform])
        sizeHeader.distribution = .fill
        uniform.setContentCompressionResistancePriority(.required, for: .horizontal)
        uniform.setContentHuggingPriority(.required, for: .horizontal)
        uniformSection = slider
        // Every side input is as wide as the other input boxes.
        func sideCell(_ name: String, _ input: NumberInput) -> NSView {
            let c = input.labeled(name, centered: true)
            c.widthAnchor.constraint(equalToConstant: SidebarMetrics.columnWidth).isActive = true
            return c
        }
        let middle = NSStackView(views: [sideCell("Left", left), sideCell("Right", right)])
        middle.spacing = SidebarMetrics.columnSpacing
        let cross = NSStackView(views: [sideCell("Top", top), middle, sideCell("Bottom", bottom)])
        cross.orientation = .vertical; cross.alignment = .centerX; cross.spacing = 6
        individualSection = cross
        bezel.widthAnchor.constraint(equalToConstant: SidebarMetrics.columnWidth).isActive = true
        let bezelRow = NSStackView(views: [bezel, NSView()])
        bezelRow.distribution = .fill
        let bezelSection = stack([sectionTitle("Bezel"), sizeHeader, bezelRow, uniformSection, individualSection, colorRow("Bezel Color", bezelColor), showBezel], spacing: 8)
        let appearance = section("Appearance", [colorRow("Display Color", displayColor)])

        // Only a virtual display shows this: it can be handed to a connected display, or deleted.
        assignMenu.pullsDown = true
        assignMenu.target = self; assignMenu.action = #selector(assignChosen)
        deleteVirtualButton.bezelStyle = .rounded
        deleteVirtualButton.target = self; deleteVirtualButton.action = #selector(deleteVirtualTapped)
        virtualNote.font = .systemFont(ofSize: 11); virtualNote.textColor = .secondaryLabelColor
        keepCheckbox.target = self; keepCheckbox.action = #selector(keepChanged)
        let keepNote = NSTextField(wrappingLabelWithString: "Leaves a stand-in in the layout when this display is unplugged, and takes over again when it returns.")
        keepNote.font = .systemFont(ofSize: 11); keepNote.textColor = .secondaryLabelColor
        connectionSection = stack([divider(), section("Connection", [keepCheckbox, keepNote])], spacing: 12)
        virtualSection = stack([divider(), section("Virtual Display", [virtualNote, assignMenu, deleteVirtualButton])], spacing: 12)
        virtualSection.isHidden = true
        connectionSection.isHidden = true

        let content = stack([header, stack([nickname, detected], spacing: 4), infoSection, divider(), dimensions, divider(), bezelSection, divider(), appearance, connectionSection, virtualSection], spacing: 12)
        content.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: SidebarMetrics.inspectorInset),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -SidebarMetrics.inspectorInset),
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
    /// Two inputs side by side, each exactly one column wide, so rows line up like a grid.
    private func grid(_ a: NSView, _ b: NSView) -> NSStackView {
        for v in [a, b] { v.widthAnchor.constraint(equalToConstant: SidebarMetrics.columnWidth).isActive = true }
        let row = NSStackView(views: [a, b])
        row.spacing = SidebarMetrics.columnSpacing
        row.alignment = .top
        row.distribution = .fill
        return row
    }
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
            virtualSection.isHidden = true
            connectionSection.isHidden = true
            nickname.stringValue = ""; detected.stringValue = ""
            for input in [width, height, diagonal, x, y, bezel, top, bottom, left, right] { input.clear() }
            aspectField.stringValue = ""; detectedRow.isHidden = true
            resolution.stringValue = "—"; ppi.stringValue = "—"; role.stringValue = "—"; orientation.stringValue = "—"
            isLocked = false
            updateLockButton(); applyEnabled()
            return
        }
        hasDisplay = true
        isLocked = d.isLocked
        if nickname.currentEditor() == nil { nickname.stringValue = d.nickname }
        detected.stringValue = d.isRemembered ? "(disconnected)" : d.isVirtual ? "(virtual display)" : "(" + DisplayInfo.displayName(for: d.displayID) + ")"
        width.value = d.physicalWidthInches; height.value = d.physicalHeightInches
        diagonal.value = (d.physicalWidthInches * d.physicalWidthInches + d.physicalHeightInches * d.physicalHeightInches).squareRoot()
        shownAspect = AspectRatio.string(d.physicalWidthInches / max(d.physicalHeightInches, 0.0001))
        if aspectField.currentEditor() == nil { aspectField.stringValue = shownAspect }
        aspectIsLocked = d.aspectLocked
        updateAspectLockButton()
        let showDetected = !d.isVirtual && d.differsFromDetected
        detectedRow.isHidden = !showDetected
        detectedLabel.stringValue = "Detected \(MeasurementFormat.string(d.detectedWidthInches)) × \(MeasurementFormat.string(d.detectedHeightInches)) in"
        x.value = Double(px); y.value = Double(py)
        uniform.state = d.uniformBezel ? .on : .off
        bezel.value = d.bezelUniform; slider.doubleValue = d.bezelUniform
        top.value = d.bezelTop; bottom.value = d.bezelBottom
        left.value = d.bezelLeft; right.value = d.bezelRight
        sizeCaption.isHidden = !d.uniformBezel; bezel.superview?.isHidden = !d.uniformBezel; uniformSection.isHidden = !d.uniformBezel; individualSection.isHidden = d.uniformBezel
        displayColor.setColor(NSColor(displayHex: d.colorHex))
        bezelColor.setColor(NSColor(displayHex: d.bezelColorHex))
        showBezel.state = d.showBezel ? .on : .off
        resolution.stringValue = "\(d.pixelWidth) × \(d.pixelHeight) pixels"; ppi.stringValue = String(format: "%.0f PPI", d.ppi)
        role.stringValue = d.isRemembered ? "Disconnected display" : d.isVirtual ? "Virtual display" : (d.isPrimary ? "Primary display" : "Secondary display")
        virtualSection.isHidden = !d.isVirtual
        connectionSection.isHidden = d.isVirtual
        keepCheckbox.state = d.keepWhenDisconnected ? .on : .off
        virtualNote.stringValue = d.isRemembered
            ? "This display isn't connected. It takes this place again when plugged back in. Assign to move it onto a different display."
            : "Not connected. Assign it to a connected display to move this place, size and look onto it."
        deleteVirtualButton.title = d.isRemembered ? "Forget Display" : "Delete Virtual Display"
        if d.isVirtual { rebuildAssignMenu() }
        orientation.stringValue = d.isPortrait ? "Portrait (rotated \(d.rotationDegrees)°)" : (d.rotationDegrees == 0 ? "Landscape" : "Landscape (rotated \(d.rotationDegrees)°)")
        if d.mirrorsDisplayID != 0 { role.stringValue += ", mirroring \(DisplayInfo.displayName(for: d.mirrorsDisplayID))" }
        updateLockButton(); applyEnabled()
    }

    /// Everything except the lock is read-only while the display is locked or nothing is selected.
    private func applyEnabled() {
        let editable = hasDisplay && !isLocked
        for input in [width, height, diagonal, x, y, top, bottom, left, right] { input.isEnabled = editable }
        aspectField.isEnabled = editable; aspectLockButton.isEnabled = editable; resetButton.isEnabled = editable
        // The single size is hidden, not just disabled, while individual sides are shown.
        bezel.isEnabled = editable
        nickname.isEnabled = editable; uniform.isEnabled = editable; slider.isEnabled = editable
        bezelColor.isEnabled = editable; displayColor.isEnabled = editable
        // Settings can force every bezel on or off, which takes this display's own switch out of play.
        let overridden = BezelVisibility.current != .perDisplay
        // Stays clickable while a global setting overrides it; it just looks dimmed.
        showBezel.isEnabled = editable
        showBezel.alphaValue = overridden ? 0.45 : 1
        showBezel.toolTip = overridden ? "All bezels are currently forced \(BezelVisibility.current == .showAll ? "on" : "off") in Settings." : nil
        lockButton.isEnabled = hasDisplay
        deleteVirtualButton.isEnabled = editable
        keepCheckbox.isEnabled = editable
        assignMenu.isEnabled = editable && !connectedDisplays.isEmpty
    }

    private func updateLockButton() {
        let name = isLocked ? "lock.fill" : "lock.open"
        lockButton.image = NSImage(systemSymbolName: name, accessibilityDescription: isLocked ? "Unlock display" : "Lock display")
        lockButton.contentTintColor = isLocked ? .labelColor : .secondaryLabelColor
        lockButton.toolTip = isLocked ? "Locked – click to allow changes" : "Lock this display to prevent changes"
    }

    // MARK: - Actions

    private func rebuildAssignMenu() {
        assignMenu.removeAllItems()
        assignMenu.addItem(withTitle: connectedDisplays.isEmpty ? "No connected displays" : "Assign to Connected Display…")
        for display in connectedDisplays {
            let item = NSMenuItem(title: display.name, action: nil, keyEquivalent: "")
            item.tag = Int(display.id)
            assignMenu.menu?.addItem(item)
        }
        assignMenu.isEnabled = hasDisplay && !isLocked && !connectedDisplays.isEmpty
    }
    @objc private func assignChosen() {
        guard let item = assignMenu.selectedItem, item.tag != 0 else { return }
        onAssignVirtual?(CGDirectDisplayID(item.tag))
    }
    @objc private func keepChanged() { emit(DisplayEdit(keepWhenDisconnected: keepCheckbox.state == .on)) }
    @objc private func deleteVirtualTapped() { onDeleteVirtual?() }
    private func emit(_ edit: DisplayEdit) { onChange?(edit) }
    @objc private func aspectEdited() {
        // Text that isn't a ratio puts the current one back.
        guard let ratio = AspectRatio.parse(aspectField.stringValue) else {
            aspectField.stringValue = shownAspect
            return
        }
        emit(DisplayEdit(aspect: ratio))
    }
    @objc private func aspectLockToggled() { emit(DisplayEdit(aspectLocked: !aspectIsLocked)) }
    @objc private func resetToDetected() { emit(DisplayEdit(resetToDetected: true)) }
    private func updateAspectLockButton() {
        aspectLockButton.image = NSImage(systemSymbolName: aspectIsLocked ? "lock.fill" : "lock.open", accessibilityDescription: aspectIsLocked ? "Unlock aspect ratio" : "Lock aspect ratio")
        aspectLockButton.contentTintColor = aspectIsLocked ? .labelColor : .secondaryLabelColor
        aspectLockButton.toolTip = aspectIsLocked ? "Aspect ratio locked – changing one size changes the other" : "Lock the aspect ratio so changing one size changes the other"
    }
    @objc private func lockToggled() { emit(DisplayEdit(isLocked: !isLocked)) }
    @objc private func nameChanged() { emit(DisplayEdit(nickname: nickname.stringValue)) }
    @objc private func uniformChanged() { emit(DisplayEdit(uniformBezel: uniform.state == .on)) }
    @objc private func showBezelChanged() { emit(DisplayEdit(showBezel: showBezel.state == .on)) }
    @objc private func sliderChanged() {
        // A detent at zero makes it easy to land on no bezel.
        if abs(slider.doubleValue) < 0.04 { slider.doubleValue = 0 }
        setUniformBezel(slider.doubleValue)
    }
    /// Sets the uniform size only; the four individual sides are kept for when Uniform is switched off.
    private func setUniformBezel(_ v: Double) {
        bezel.value = v; slider.doubleValue = v
        emit(DisplayEdit(bezelUniform: v))
    }
}
