//
//  DisplaysPanel.swift
//  ScreenBean
//
//  A list of every display in the layout, as rows or as thumbnails, for the left sidebar.
//  Clicking one selects it in the workspace (Shift-click adds to the selection).
//

import Cocoa

/// What the panel shows about one display.
struct DisplaySummary: Equatable {
    var id: CGDirectDisplayID
    var label: String
    var name: String
    var colorHex: String
    var pixelWidth: Int
    var pixelHeight: Int
    var widthInches: Double
    var heightInches: Double
    var isVirtual: Bool
    var isRemembered: Bool
    var isPrimary: Bool

    var resolutionText: String { "\(pixelWidth) × \(pixelHeight)" }

    /// "Primary", "Virtual", "Disconnected", or nothing special.
    var statusText: String? {
        isRemembered ? "Disconnected" : isVirtual ? "Virtual" : isPrimary ? "Primary" : nil
    }
}

final class DisplaysPanel: NSView {
    /// Called with a display to select, and whether to add it to the selection.
    var onSelect: ((CGDirectDisplayID, Bool) -> Void)?
    /// Called when the collapse button is clicked.
    var onCollapse: (() -> Void)?

    private enum Mode: Int { case list, thumbnails }
    private static let modeKey = "ScreenBean.DisplaysPanelMode"

    private let collapseButton = NSButton()
    private let countLabel = NSTextField(labelWithString: "")
    private let modeControl = NSSegmentedControl(images: [
        NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "List") ?? NSImage(),
        NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Thumbnails") ?? NSImage()
    ], trackingMode: .selectOne, target: nil, action: nil)
    private let body = NSStackView()

    private var summaries: [DisplaySummary] = []
    private var selected: Set<CGDirectDisplayID> = []

    private var mode: Mode {
        get { Mode(rawValue: UserDefaults.standard.integer(forKey: Self.modeKey)) ?? .list }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.modeKey) }
    }

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    // MARK: - Layout

    private func build() {
        let title = NSTextField(labelWithString: "Displays")
        title.font = .boldSystemFont(ofSize: 14)
        countLabel.font = .systemFont(ofSize: 11); countLabel.textColor = .secondaryLabelColor
        collapseButton.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Hide displays")
        collapseButton.isBordered = false
        collapseButton.contentTintColor = .secondaryLabelColor
        collapseButton.target = self; collapseButton.action = #selector(collapseClicked)
        collapseButton.toolTip = "Hide the displays sidebar"
        modeControl.selectedSegment = mode.rawValue
        modeControl.target = self; modeControl.action = #selector(modeChanged)
        modeControl.controlSize = .small
        modeControl.segmentStyle = .texturedRounded
        modeControl.toolTip = "List or thumbnails"
        let header = NSStackView(views: [title, countLabel, NSView(), modeControl, collapseButton])
        header.spacing = 6
        header.distribution = .fill
        header.alignment = .centerY

        body.orientation = .vertical; body.alignment = .leading; body.spacing = 4

        let stack = NSStackView(views: [header, body])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Shows the displays. Does nothing if nothing about them has changed, so dragging in the
    /// workspace doesn't rebuild the rows.
    func update(_ newSummaries: [DisplaySummary], selected newSelected: Set<CGDirectDisplayID>) {
        guard newSummaries != summaries || newSelected != selected else { return }
        summaries = newSummaries
        selected = newSelected
        countLabel.stringValue = "(\(summaries.count))"
        rebuildRows()
    }

    private func rebuildRows() {
        for view in body.arrangedSubviews { body.removeArrangedSubview(view); view.removeFromSuperview() }
        switch mode {
        case .list:
            for summary in summaries {
                let row = DisplayListRow(summary: summary, isSelected: selected.contains(summary.id))
                row.onClick = { [weak self] id, extend in self?.onSelect?(id, extend) }
                body.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
            }
        case .thumbnails:
            // Two tiles to a row.
            for start in stride(from: 0, to: summaries.count, by: 2) {
                let tiles = summaries[start..<min(start + 2, summaries.count)].map { summary -> DisplayTile in
                    let tile = DisplayTile(summary: summary, isSelected: selected.contains(summary.id))
                    tile.onClick = { [weak self] id, extend in self?.onSelect?(id, extend) }
                    return tile
                }
                let row = NSStackView(views: tiles)
                row.spacing = 8
                row.distribution = .fillEqually
                body.addArrangedSubview(row)
                if tiles.count == 1 {
                    // A lone tile keeps the width of a pair's.
                    tiles[0].widthAnchor.constraint(equalTo: body.widthAnchor, multiplier: 0.5, constant: -4).isActive = true
                } else {
                    row.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
                }
            }
        }
        if summaries.isEmpty {
            let empty = NSTextField(labelWithString: "No displays")
            empty.font = .systemFont(ofSize: 11); empty.textColor = .secondaryLabelColor
            body.addArrangedSubview(empty)
        }
    }

    @objc private func collapseClicked() { onCollapse?() }

    @objc private func modeChanged() {
        mode = Mode(rawValue: modeControl.selectedSegment) ?? .list
        rebuildRows()
    }
}

// MARK: - Rows and tiles

/// Shared behavior: clickable, with a highlight while selected.
private class DisplayItemView: NSView {
    let summary: DisplaySummary
    let isSelected: Bool
    var onClick: ((CGDirectDisplayID, Bool) -> Void)?

    init(summary: DisplaySummary, isSelected: Bool) {
        self.summary = summary
        self.isSelected = isSelected
        super.init(frame: .zero)
        toolTip = summary.name
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?(summary.id, event.modifierFlags.contains(.shift)) }

    func drawHighlight() {
        guard isSelected else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    func attributes(size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor, alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = alignment
        return [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style]
    }
}

/// One display as a row: a colored badge with its letter, its name, and its resolution and size.
private final class DisplayListRow: DisplayItemView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 38) }

    override func draw(_ dirtyRect: NSRect) {
        drawHighlight()
        let badge = CGRect(x: 6, y: (bounds.height - 24) / 2, width: 24, height: 24)
        NSColor(displayHex: summary.colorHex).setFill()
        NSBezierPath(ovalIn: badge).fill()
        NSColor.black.withAlphaComponent(0.25).setStroke()
        NSBezierPath(ovalIn: badge.insetBy(dx: 0.5, dy: 0.5)).stroke()
        let letter = NSAttributedString(string: summary.label, attributes: attributes(size: 12, weight: .bold, color: NSColor.black.withAlphaComponent(0.7), alignment: .center))
        let size = letter.size()
        letter.draw(at: CGPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2))

        var textRight = bounds.width - 6
        if summary.isVirtual, let symbol = NSImage(systemSymbolName: "square.dashed", accessibilityDescription: "Virtual display")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor])) {
            symbol.draw(in: CGRect(x: bounds.width - 22, y: (bounds.height - 14) / 2, width: 14, height: 14))
            textRight -= 20
        }
        let textLeft: CGFloat = 38
        let width = max(textRight - textLeft, 0)
        NSAttributedString(string: summary.name, attributes: attributes(size: 12, weight: .medium))
            .draw(in: CGRect(x: textLeft, y: 4, width: width, height: 16))
        let detail = [summary.resolutionText, MeasurementFormat.pair(summary.widthInches, summary.heightInches), summary.statusText].compactMap { $0 }.joined(separator: " · ")
        NSAttributedString(string: detail, attributes: attributes(size: 10, color: .secondaryLabelColor))
            .draw(in: CGRect(x: textLeft, y: 21, width: width, height: 14))
    }
}

/// One display as a thumbnail: its shape, drawn to relative scale in its color, with its name and resolution below.
private final class DisplayTile: DisplayItemView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 96) }

    override func draw(_ dirtyRect: NSRect) {
        drawHighlight()
        // The shape keeps the display's proportions inside a fixed box.
        let box = CGRect(x: 8, y: 6, width: max(bounds.width - 16, 10), height: 54)
        let ratio = summary.widthInches / max(summary.heightInches, 0.0001)
        var shape = CGSize(width: box.width, height: box.width / ratio)
        if shape.height > box.height { shape = CGSize(width: box.height * ratio, height: box.height) }
        let frame = CGRect(x: box.midX - shape.width / 2, y: box.midY - shape.height / 2, width: shape.width, height: shape.height)
        let path = NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3)
        if let context = NSGraphicsContext.current?.cgContext, let gradient = DisplayGradient.make(hex: summary.colorHex) {
            context.saveGState()
            path.addClip()
            // This view is flipped, so the gradient runs top-left to bottom-right.
            context.drawLinearGradient(gradient, start: CGPoint(x: frame.minX, y: frame.minY), end: CGPoint(x: frame.maxX, y: frame.maxY), options: [])
            context.restoreGState()
        } else {
            NSColor(displayHex: summary.colorHex).setFill()
            path.fill()
        }
        NSColor.black.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()
        if summary.isVirtual {
            let dashed = NSBezierPath(roundedRect: frame.insetBy(dx: 2, dy: 2), xRadius: 2, yRadius: 2)
            dashed.setLineDash([3, 2], count: 2, phase: 0)
            dashed.lineWidth = 1
            NSColor.white.withAlphaComponent(0.7).setStroke()
            dashed.stroke()
        }
        let letter = NSAttributedString(string: summary.label, attributes: attributes(size: min(frame.height * 0.5, 22), weight: .bold, color: NSColor.black.withAlphaComponent(0.4), alignment: .center))
        let size = letter.size()
        letter.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))

        NSAttributedString(string: summary.name, attributes: attributes(size: 11, weight: .medium, alignment: .center))
            .draw(in: CGRect(x: 4, y: 64, width: bounds.width - 8, height: 15))
        let detail = [summary.resolutionText, summary.statusText].compactMap { $0 }.joined(separator: " · ")
        NSAttributedString(string: detail, attributes: attributes(size: 10, color: .secondaryLabelColor, alignment: .center))
            .draw(in: CGRect(x: 4, y: 79, width: bounds.width - 8, height: 14))
    }
}
