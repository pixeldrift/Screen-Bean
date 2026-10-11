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

        let stack = NSStackView(views: [title, identifyRow, fractions, bezelRow])
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

    @objc private func fractionsToggled() { MeasurementFormat.useFractions = fractionsSwitch.state == .on }

    @objc private func bezelChanged() { BezelVisibility.current = BezelVisibility(rawValue: bezelControl.selectedSegment) ?? .perDisplay }
}
