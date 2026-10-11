//
//  VirtualDisplayPrompt.swift
//  ScreenBean
//
//  The dialog that asks for a planned display's name and size.
//

import Cocoa

struct VirtualDisplaySpec {
    var name: String
    var widthInches: Double
    var heightInches: Double
    var pixelWidth: Int
    var pixelHeight: Int
}

enum VirtualDisplayPrompt {
    /// Asks for the new display's details. Returns nil if cancelled or the sizes aren't usable.
    static func run() -> VirtualDisplaySpec? {
        let name = NSTextField(string: "Virtual Display")
        // A 27-inch 16:9 monitor, a common starting point.
        let width = NSTextField(string: MeasurementFormat.string(23.5))
        let height = NSTextField(string: MeasurementFormat.string(13.2))
        let pixelWidth = NSTextField(string: "2560")
        let pixelHeight = NSTextField(string: "1440")

        func row(_ title: String, _ fields: [NSTextField]) -> NSStackView {
            let label = NSTextField(labelWithString: title)
            label.widthAnchor.constraint(equalToConstant: 110).isActive = true
            let row = NSStackView(views: [label] + fields)
            row.spacing = 8
            for field in fields { field.widthAnchor.constraint(equalToConstant: fields.count == 1 ? 190 : 90).isActive = true }
            return row
        }
        let form = NSStackView(views: [
            row("Name", [name]),
            row("Size (inches)", [width, height]),
            row("Resolution (px)", [pixelWidth, pixelHeight])
        ])
        form.orientation = .vertical; form.alignment = .leading; form.spacing = 8
        form.frame = NSRect(x: 0, y: 0, width: 320, height: 90)

        let alert = NSAlert()
        alert.messageText = "Add Virtual Display"
        alert.informativeText = "A planned display that isn't connected. Width and height are the visible panel in inches."
        alert.accessoryView = form
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        guard let w = MeasurementFormat.parse(width.stringValue), let h = MeasurementFormat.parse(height.stringValue), w > 0.1, h > 0.1,
              let pw = Int(pixelWidth.stringValue.trimmingCharacters(in: .whitespaces)), let ph = Int(pixelHeight.stringValue.trimmingCharacters(in: .whitespaces)), pw > 0, ph > 0 else {
            let warning = NSAlert()
            warning.messageText = "Those sizes can't be used"
            warning.informativeText = "Enter a width and height in inches, and a resolution in whole pixels."
            warning.alertStyle = .warning
            warning.runModal()
            return nil
        }
        let trimmed = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return VirtualDisplaySpec(name: trimmed.isEmpty ? "Virtual Display" : trimmed, widthInches: w, heightInches: h, pixelWidth: pw, pixelHeight: ph)
    }
}
