//
//  SettingsPanel.swift
//  ScreenBean
//
//  The sidebar's Settings section: identify mode, how measurements and bezels are shown.
//

import Cocoa

final class SettingsPanel: NSView {
    let identifyButton = NSButton(title: "Identify Displays", target: nil, action: nil)
    let excludePrimaryCheckbox = NSButton(checkboxWithTitle: "Exclude primary", target: nil, action: nil)

    private let fractionsSwitch = NSSwitch()
    private let guidesSwitch = NSSwitch()
    private let edgeGuidesCheckbox = NSButton(checkboxWithTitle: "Edge guides", target: nil, action: nil)
    private let edgeScopeControl = NSSegmentedControl(labels: ["All displays", "Selected"], trackingMode: .selectOne, target: nil, action: nil)
    private let onScreensCheckbox = NSButton(checkboxWithTitle: "Show on real screens", target: nil, action: nil)
    private let gapMeasurementsCheckbox = NSButton(checkboxWithTitle: "Gap measurements", target: nil, action: nil)
    private let clearGuidesButton = NSButton(title: "Clear Custom Guides", target: nil, action: nil)
    private let bezelControl = NSSegmentedControl(labels: ["Per display", "Show all", "Hide all"], trackingMode: .selectOne, target: nil, action: nil)

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
        let identifyRow = NSStackView(views: [identifyButton, excludePrimaryCheckbox])
        identifyRow.spacing = 12
        identifyRow.alignment = .centerY

        // Measurements.
        fractionsSwitch.target = self; fractionsSwitch.action = #selector(fractionsToggled)
        fractionsSwitch.state = MeasurementFormat.useFractions ? .on : .off
        let fractionsLabel = NSTextField(labelWithString: "Show as Fractions")
        fractionsLabel.font = .systemFont(ofSize: 12)
        let fractionsRow = NSStackView(views: [fractionsSwitch, fractionsLabel])
        fractionsRow.spacing = 8
        fractionsRow.alignment = .centerY
        let fractionsNote = NSTextField(labelWithString: "Fractions always accepted as input")
        fractionsNote.font = .systemFont(ofSize: 10)
        fractionsNote.textColor = .tertiaryLabelColor
        let fractions = NSStackView(views: [fractionsRow, fractionsNote])
        fractions.orientation = .vertical; fractions.alignment = .leading; fractions.spacing = 2
        NotificationCenter.default.addObserver(forName: MeasurementFormat.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.fractionsSwitch.state = MeasurementFormat.useFractions ? .on : .off
        }

        // Bezels: a global override over each display's own Show bezel setting.
        let bezelLabel = NSTextField(labelWithString: "Bezels")
        bezelLabel.font = .systemFont(ofSize: 12)
        bezelControl.selectedSegment = BezelVisibility.current.rawValue
        bezelControl.target = self; bezelControl.action = #selector(bezelChanged)
        bezelControl.toolTip = "Show or hide every display's bezel, overriding each display's own setting."
        let bezelRow = NSStackView(views: [bezelLabel, bezelControl])
        bezelRow.spacing = 8
        bezelRow.alignment = .centerY

        // Guides: toggles live here; they are created by dragging out of the rulers.
        let guidesLabel = NSTextField(labelWithString: "Guides")
        guidesLabel.font = .systemFont(ofSize: 12)
        guidesSwitch.target = self; guidesSwitch.action = #selector(guidesToggled)
        guidesSwitch.toolTip = "Show or hide all guides. Drag from a ruler to add one; drag it back to delete it."
        let guidesRow = NSStackView(views: [guidesSwitch, guidesLabel])
        guidesRow.spacing = 8
        guidesRow.alignment = .centerY
        edgeGuidesCheckbox.target = self; edgeGuidesCheckbox.action = #selector(edgeGuidesToggled)
        edgeGuidesCheckbox.toolTip = "Continue each display's edges across the whole canvas."
        edgeScopeControl.target = self; edgeScopeControl.action = #selector(edgeScopeChanged)
        edgeScopeControl.controlSize = .small
        let edgeRow = NSStackView(views: [edgeGuidesCheckbox, edgeScopeControl])
        edgeRow.spacing = 8
        edgeRow.alignment = .centerY
        onScreensCheckbox.target = self; onScreensCheckbox.action = #selector(onScreensToggled)
        onScreensCheckbox.toolTip = "Draw the guides on the real displays so they line up across screens in space."
        gapMeasurementsCheckbox.target = self; gapMeasurementsCheckbox.action = #selector(gapMeasurementsToggled)
        gapMeasurementsCheckbox.toolTip = "Show the distance across empty space between displays. Drag an arrow to move a display or slide it along the gap."
        clearGuidesButton.bezelStyle = .rounded
        clearGuidesButton.controlSize = .small
        clearGuidesButton.target = self; clearGuidesButton.action = #selector(clearGuides)
        let guides = NSStackView(views: [guidesRow, edgeRow, onScreensCheckbox, gapMeasurementsCheckbox, clearGuidesButton])
        guides.orientation = .vertical; guides.alignment = .leading; guides.spacing = 6
        NotificationCenter.default.addObserver(forName: GuideSettings.didChange, object: nil, queue: .main) { [weak self] _ in self?.syncGuideControls() }
        syncGuideControls()

        let stack = NSStackView(views: [title, identifyRow, fractions, bezelRow, guides])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func syncGuideControls() {
        guidesSwitch.state = GuideSettings.showGuides ? .on : .off
        edgeGuidesCheckbox.state = GuideSettings.showEdgeGuides ? .on : .off
        edgeScopeControl.selectedSegment = GuideSettings.edgeScope.rawValue
        onScreensCheckbox.state = GuideSettings.showOnScreens ? .on : .off
        gapMeasurementsCheckbox.state = GuideSettings.showGapMeasurements ? .on : .off
        let enabled = GuideSettings.showGuides
        edgeGuidesCheckbox.isEnabled = enabled
        edgeScopeControl.isEnabled = enabled && GuideSettings.showEdgeGuides
        onScreensCheckbox.isEnabled = enabled
    }

    @objc private func guidesToggled() { GuideSettings.showGuides = guidesSwitch.state == .on }
    @objc private func edgeGuidesToggled() { GuideSettings.showEdgeGuides = edgeGuidesCheckbox.state == .on }
    @objc private func edgeScopeChanged() { GuideSettings.edgeScope = EdgeGuideScope(rawValue: edgeScopeControl.selectedSegment) ?? .allDisplays }
    @objc private func onScreensToggled() { GuideSettings.showOnScreens = onScreensCheckbox.state == .on }
    @objc private func gapMeasurementsToggled() { GuideSettings.showGapMeasurements = gapMeasurementsCheckbox.state == .on }
    @objc private func clearGuides() { GuideStore.shared.removeAll() }

    @objc private func fractionsToggled() { MeasurementFormat.useFractions = fractionsSwitch.state == .on }

    @objc private func bezelChanged() { BezelVisibility.current = BezelVisibility(rawValue: bezelControl.selectedSegment) ?? .perDisplay }
}
