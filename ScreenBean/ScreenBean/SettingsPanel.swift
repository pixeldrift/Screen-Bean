//
//  SettingsPanel.swift
//  ScreenBean
//
//  The sidebar's Settings section: identify mode, how measurements and bezels are
//  shown, which guides are visible, and snapping.
//

import Cocoa

final class SettingsPanel: NSView {
    let identifyButton = NSButton(title: "Identify Displays", target: nil, action: nil)
    let excludePrimaryCheckbox = NSButton(checkboxWithTitle: "Exclude main", target: nil, action: nil)

    private let unitControl = NSSegmentedControl(labels: ["Inches", "Centimeters"], trackingMode: .selectOne, target: nil, action: nil)
    private let fractionsCheckbox = NSButton(checkboxWithTitle: "Show units as fractions", target: nil, action: nil)
    private let rulersCheckbox = NSButton(checkboxWithTitle: "Show Rulers", target: nil, action: nil)
    private let transitCheckbox = NSButton(checkboxWithTitle: "Show Mouse Transit", target: nil, action: nil)
    private let transitScreensCheckbox = NSButton(checkboxWithTitle: "Show Transit on Screens", target: nil, action: nil)
    private let mappingCheckbox = NSButton(checkboxWithTitle: "Enable Mouse Mapping", target: nil, action: nil)
    private let mappingNote = NSTextField(wrappingLabelWithString: "")
    /// Called when Enable Mouse Mapping is switched.
    var onMappingToggled: ((Bool) -> Void)?
    private let bezelControl = NSSegmentedControl(labels: ["All", "Per display", "None"], trackingMode: .selectOne, target: nil, action: nil)
    private let edgeGuidesCheckbox = NSButton(checkboxWithTitle: "Edge guides", target: nil, action: nil)
    private let edgeScopeControl = NSSegmentedControl(labels: ["All", "Selected"], trackingMode: .selectOne, target: nil, action: nil)
    private let gapGuidesCheckbox = NSButton(checkboxWithTitle: "Gap guides", target: nil, action: nil)
    private let customGuidesCheckbox = NSButton(checkboxWithTitle: "Custom guides", target: nil, action: nil)
    private let snapGuidesCheckbox = NSButton(checkboxWithTitle: "Snap to guides", target: nil, action: nil)
    private let snapBezelsCheckbox = NSButton(checkboxWithTitle: "Snap to bezels", target: nil, action: nil)
    private let clearGuidesButton = NSButton(title: "Clear Custom Guides", target: nil, action: nil)

    /// The bezel control's segments, in the order shown.
    private let bezelChoices: [BezelVisibility] = [.showAll, .perDisplay, .hideAll]

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        let title = NSTextField(labelWithString: "ScreenBean Settings")
        title.font = .boldSystemFont(ofSize: 16)

        // Identify mode stays on, even while you click around, until the button is switched off.
        identifyButton.setButtonType(.pushOnPushOff)
        identifyButton.bezelStyle = .rounded
        identifyButton.toolTip = "Fill each real screen with its letter, name and size. Ends on any click or key press."
        excludePrimaryCheckbox.toolTip = "Leave the main (primary) display clear while identifying."
        let identify = NSStackView(views: [identifyButton, excludePrimaryCheckbox])
        identify.spacing = 10
        identify.alignment = .centerY

        // Measurements: the unit, and (for inches) whether to show fractions.
        let unitLabel = NSTextField(labelWithString: "Measurement Units")
        unitLabel.font = .systemFont(ofSize: 12)
        unitControl.target = self; unitControl.action = #selector(unitChanged)
        unitControl.toolTip = "Show lengths in inches or centimeters. Layouts are kept in inches either way, and a unit typed after a number (cm, mm, in) is always understood."
        let units = vertical([unitLabel, unitControl], spacing: 4)
        fractionsCheckbox.target = self; fractionsCheckbox.action = #selector(fractionsToggled)
        let fractionsNote = NSTextField(labelWithString: "Fractions always accepted as input")
        fractionsNote.font = .systemFont(ofSize: 10)
        fractionsNote.textColor = .tertiaryLabelColor
        let fractions = vertical([fractionsCheckbox, fractionsNote], spacing: 2)
        syncFractions()
        NotificationCenter.default.addObserver(forName: MeasurementFormat.didChange, object: nil, queue: .main) { [weak self] _ in self?.syncFractions() }

        rulersCheckbox.target = self; rulersCheckbox.action = #selector(rulersToggled)
        rulersCheckbox.toolTip = "Rulers along the top and left of the workspace. Drag from one to create a guide."

        transitCheckbox.target = self; transitCheckbox.action = #selector(transitToggled)
        transitCheckbox.toolTip = "Show where the mouse can pass from one display to the next. Select a zone to move its corner dots along the display edges."

        transitScreensCheckbox.target = self; transitScreensCheckbox.action = #selector(transitScreensToggled)
        transitScreensCheckbox.toolTip = "Draw each zone's stretch of edge on the real screens, in the color of the display it leads to, with that display's letter."
        mappingCheckbox.target = self; mappingCheckbox.action = #selector(mappingToggled)
        mappingCheckbox.toolTip = "Make the real mouse cross between displays by the transit zones. Needs Accessibility permission."
        mappingNote.font = .systemFont(ofSize: 10)
        mappingNote.textColor = .tertiaryLabelColor
        mappingNote.preferredMaxLayoutWidth = 220
        let mapping = vertical([mappingCheckbox, mappingNote], spacing: 2)

        // Bezels: a global override over each display's own Show bezel setting.
        let bezelLabel = NSTextField(labelWithString: "Show Display Bezels")
        bezelLabel.font = .systemFont(ofSize: 12)
        bezelControl.selectedSegment = bezelChoices.firstIndex(of: BezelVisibility.current) ?? 1
        bezelControl.target = self; bezelControl.action = #selector(bezelChanged)
        bezelControl.toolTip = "Show or hide every display's bezel, overriding each display's own setting."
        let bezels = vertical([bezelLabel, bezelControl], spacing: 4)

        // Guides, in the order Edge, Gap, Custom.
        let guidesLabel = NSTextField(labelWithString: "Guides")
        guidesLabel.font = .boldSystemFont(ofSize: 11)
        guidesLabel.textColor = .secondaryLabelColor
        edgeGuidesCheckbox.target = self; edgeGuidesCheckbox.action = #selector(edgeGuidesToggled)
        edgeGuidesCheckbox.toolTip = "Continue display edges across the canvas and onto the real screens."
        edgeScopeControl.target = self; edgeScopeControl.action = #selector(edgeScopeChanged)
        edgeScopeControl.controlSize = .small
        let edgeRow = NSStackView(views: [edgeGuidesCheckbox, edgeScopeControl])
        edgeRow.spacing = 8
        edgeRow.alignment = .centerY
        gapGuidesCheckbox.target = self; gapGuidesCheckbox.action = #selector(gapGuidesToggled)
        gapGuidesCheckbox.toolTip = "Show the distance across empty space between displays. Drag an arrow to move a display or slide it along the gap."
        customGuidesCheckbox.target = self; customGuidesCheckbox.action = #selector(customGuidesToggled)
        customGuidesCheckbox.toolTip = "Guides dragged out of the rulers. They show on the real screens too."
        clearGuidesButton.bezelStyle = .rounded
        clearGuidesButton.controlSize = .small
        clearGuidesButton.target = self; clearGuidesButton.action = #selector(clearGuides)

        // Snapping.
        snapGuidesCheckbox.target = self; snapGuidesCheckbox.action = #selector(snapGuidesToggled)
        snapGuidesCheckbox.toolTip = "Dragged display and image edges snap to guides. Hold Control to flip snapping for one drag."
        snapBezelsCheckbox.target = self; snapBezelsCheckbox.action = #selector(snapBezelsToggled)
        snapBezelsCheckbox.toolTip = "Dragged displays snap so their bezels touch their neighbors'. Hold Control to flip snapping for one drag."

        let guides = vertical([guidesLabel, edgeRow, gapGuidesCheckbox, customGuidesCheckbox, snapGuidesCheckbox, snapBezelsCheckbox, clearGuidesButton], spacing: 6)
        NotificationCenter.default.addObserver(forName: GuideSettings.didChange, object: nil, queue: .main) { [weak self] _ in self?.syncGuideControls() }
        syncGuideControls()

        let guidesDivider = NSBox(); guidesDivider.boxType = .separator
        let stack = vertical([title, identify, units, fractions, rulersCheckbox, transitCheckbox, transitScreensCheckbox, mapping, bezels, guidesDivider, guides], spacing: 12)
        guidesDivider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func vertical(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
        return stack
    }

    private func syncFractions() {
        fractionsCheckbox.state = MeasurementFormat.useFractions ? .on : .off
        unitControl.selectedSegment = MeasurementFormat.unit == .inches ? 0 : 1
        // Fractions are a way of writing inches.
        fractionsCheckbox.isEnabled = MeasurementFormat.unit == .inches
        fractionsCheckbox.toolTip = fractionsCheckbox.isEnabled ? nil : "Fractions apply to inches only."
    }

    private func syncGuideControls() {
        rulersCheckbox.state = GuideSettings.showRulers ? .on : .off
        transitCheckbox.state = GuideSettings.showMouseTransit ? .on : .off
        transitScreensCheckbox.state = GuideSettings.showTransitOnScreens ? .on : .off
        edgeGuidesCheckbox.state = GuideSettings.showEdgeGuides ? .on : .off
        edgeScopeControl.selectedSegment = GuideSettings.edgeScope.rawValue
        edgeScopeControl.isEnabled = GuideSettings.showEdgeGuides
        gapGuidesCheckbox.state = GuideSettings.showGapMeasurements ? .on : .off
        customGuidesCheckbox.state = GuideSettings.showCustomGuides ? .on : .off
        snapGuidesCheckbox.state = GuideSettings.snapToGuides ? .on : .off
        snapBezelsCheckbox.state = GuideSettings.snapToBezels ? .on : .off
    }

    @objc private func unitChanged() { MeasurementFormat.unit = unitControl.selectedSegment == 1 ? .centimeters : .inches }
    @objc private func fractionsToggled() { MeasurementFormat.useFractions = fractionsCheckbox.state == .on }
    /// Shows whether mouse mapping is on and what it is waiting for, without notifying `onMappingToggled`.
    func showMappingStatus(isOn: Bool, note: String) {
        mappingCheckbox.state = isOn ? .on : .off
        mappingNote.stringValue = note
    }

    @objc private func transitScreensToggled() { GuideSettings.showTransitOnScreens = transitScreensCheckbox.state == .on }
    @objc private func mappingToggled() { onMappingToggled?(mappingCheckbox.state == .on) }
    @objc private func transitToggled() { GuideSettings.showMouseTransit = transitCheckbox.state == .on }
    @objc private func rulersToggled() { GuideSettings.showRulers = rulersCheckbox.state == .on }
    @objc private func bezelChanged() { BezelVisibility.current = bezelChoices[min(max(bezelControl.selectedSegment, 0), bezelChoices.count - 1)] }
    @objc private func edgeGuidesToggled() { GuideSettings.showEdgeGuides = edgeGuidesCheckbox.state == .on }
    @objc private func edgeScopeChanged() { GuideSettings.edgeScope = EdgeGuideScope(rawValue: edgeScopeControl.selectedSegment) ?? .allDisplays }
    @objc private func gapGuidesToggled() { GuideSettings.showGapMeasurements = gapGuidesCheckbox.state == .on }
    @objc private func customGuidesToggled() { GuideSettings.showCustomGuides = customGuidesCheckbox.state == .on }
    @objc private func snapGuidesToggled() { GuideSettings.snapToGuides = snapGuidesCheckbox.state == .on }
    @objc private func snapBezelsToggled() { GuideSettings.snapToBezels = snapBezelsCheckbox.state == .on }
    @objc private func clearGuides() { UndoCenter.shared.perform("Clear Guides") { GuideStore.shared.removeAll() } }
}
