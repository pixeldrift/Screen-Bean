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
    let excludePrimaryCheckbox = NSButton(checkboxWithTitle: "Exclude primary", target: nil, action: nil)

    private let fractionsCheckbox = NSButton(checkboxWithTitle: "Show units as fractions", target: nil, action: nil)
    private let rulersCheckbox = NSButton(checkboxWithTitle: "Show Rulers", target: nil, action: nil)
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
        let title = NSTextField(labelWithString: "Settings")
        title.font = .boldSystemFont(ofSize: 14)

        // Identify mode stays on, even while you click around, until the button is switched off.
        identifyButton.setButtonType(.pushOnPushOff)
        identifyButton.bezelStyle = .rounded
        identifyButton.toolTip = "Fill each real screen with its letter, name and size. Ends on any click or key press."
        excludePrimaryCheckbox.toolTip = "Leave the primary display clear while identifying."
        let identify = vertical([identifyButton, excludePrimaryCheckbox], spacing: 6)

        // Measurements.
        fractionsCheckbox.target = self; fractionsCheckbox.action = #selector(fractionsToggled)
        let fractionsNote = NSTextField(labelWithString: "Fractions always accepted as input")
        fractionsNote.font = .systemFont(ofSize: 10)
        fractionsNote.textColor = .tertiaryLabelColor
        let fractions = vertical([fractionsCheckbox, fractionsNote], spacing: 2)
        syncFractions()
        NotificationCenter.default.addObserver(forName: MeasurementFormat.didChange, object: nil, queue: .main) { [weak self] _ in self?.syncFractions() }

        rulersCheckbox.target = self; rulersCheckbox.action = #selector(rulersToggled)
        rulersCheckbox.toolTip = "Rulers along the top and left of the workspace. Drag from one to create a guide."

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

        let stack = vertical([title, identify, fractions, rulersCheckbox, bezels, guides], spacing: 12)
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

    private func syncFractions() { fractionsCheckbox.state = MeasurementFormat.useFractions ? .on : .off }

    private func syncGuideControls() {
        rulersCheckbox.state = GuideSettings.showRulers ? .on : .off
        edgeGuidesCheckbox.state = GuideSettings.showEdgeGuides ? .on : .off
        edgeScopeControl.selectedSegment = GuideSettings.edgeScope.rawValue
        edgeScopeControl.isEnabled = GuideSettings.showEdgeGuides
        gapGuidesCheckbox.state = GuideSettings.showGapMeasurements ? .on : .off
        customGuidesCheckbox.state = GuideSettings.showCustomGuides ? .on : .off
        snapGuidesCheckbox.state = GuideSettings.snapToGuides ? .on : .off
        snapBezelsCheckbox.state = GuideSettings.snapToBezels ? .on : .off
    }

    @objc private func fractionsToggled() { MeasurementFormat.useFractions = fractionsCheckbox.state == .on }
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
