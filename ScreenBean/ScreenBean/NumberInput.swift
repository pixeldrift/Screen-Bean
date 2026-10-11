//
//  NumberInput.swift
//  ScreenBean
//
//  A numeric text field with a stepper, plus a label that scrubs the value
//  when dragged sideways.
//

import Cocoa

/// Makes Return in a text field commit the value and release keyboard focus.
final class ReturnCommitDelegate: NSObject, NSTextFieldDelegate {
    static let shared = ReturnCommitDelegate()

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        control.validateEditing()
        control.sendAction(control.action, to: control.target)
        control.window?.makeFirstResponder(nil)
        return true
    }
}

final class NumberInput: NSView {
    /// Called with the new value after the user changes it.
    var onChange: ((Double) -> Void)?
    var minimum = 0.0
    var step = 0.1 { didSet { stepper.increment = step } }
    var isEnabled = true { didSet { field.isEnabled = isEnabled; stepper.isEnabled = isEnabled } }

    private let field = NSTextField(string: "")
    private let stepper = NSStepper()

    var value: Double {
        get { field.doubleValue }
        set { field.doubleValue = newValue; stepper.doubleValue = newValue }
    }

    /// Clears the field to show there is no value (e.g. nothing selected).
    func clear() { field.stringValue = "" }

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 4
        field.formatter = formatter
        field.isBezeled = true; field.bezelStyle = .roundedBezel
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        field.target = self; field.action = #selector(fieldChanged)
        field.delegate = ReturnCommitDelegate.shared
        stepper.minValue = -100000; stepper.maxValue = 100000; stepper.increment = step
        stepper.valueWraps = false
        stepper.target = self; stepper.action = #selector(stepperChanged)
        for v in [field, stepper] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            field.trailingAnchor.constraint(equalTo: trailingAnchor),
            field.topAnchor.constraint(equalTo: topAnchor),
            field.bottomAnchor.constraint(equalTo: bottomAnchor),
            stepper.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stepper.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    /// This input under a scrubbable caption, e.g. "Width (inches)".
    func labeled(_ text: String, unit: String? = nil, centered: Bool = false) -> NSView {
        let label = ScrubLabel(text, unit: unit, input: self)
        if centered { label.alignment = .center }
        let stack = NSStackView(views: [label, self])
        stack.orientation = .vertical; stack.alignment = .width; stack.spacing = 4
        return stack
    }

    /// Applies a drag or stepper change, respecting the minimum.
    func nudge(by delta: Double) {
        value = max(minimum, value + delta)
        onChange?(value)
    }

    @objc private func fieldChanged() {
        value = max(minimum, field.doubleValue)
        onChange?(value)
    }

    @objc private func stepperChanged() {
        value = max(minimum, stepper.doubleValue)
        onChange?(value)
    }
}

/// A caption that changes a `NumberInput` when dragged left or right.
final class ScrubLabel: NSTextField {
    weak var input: NumberInput?
    var scrubScale = 0.05
    private var lastX: CGFloat = 0

    convenience init(_ text: String, unit: String? = nil, input: NumberInput) {
        self.init(labelWithString: text)
        self.input = input
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        if let unit {
            attributed.append(NSAttributedString(string: " (\(unit))", attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        attributedStringValue = attributed
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func mouseDown(with event: NSEvent) { lastX = event.locationInWindow.x }
    override func mouseDragged(with event: NSEvent) {
        guard let input, input.isEnabled else { return }
        let x = event.locationInWindow.x
        input.nudge(by: Double(x - lastX) * scrubScale)
        lastX = x
    }
}

/// Two equal-width columns, used for pairs of labeled inputs.
func twoColumnGrid(_ a: NSView, _ b: NSView) -> NSStackView {
    let stack = NSStackView(views: [a, b])
    stack.distribution = .fillEqually; stack.spacing = 16; stack.alignment = .top
    return stack
}
