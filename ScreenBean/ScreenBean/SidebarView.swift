//
//  SidebarView.swift
//  ScreenBean
//
//  Right-hand sidebar. Shows the display inspector while a display is
//  selected; otherwise shows tabs for workspace-wide tools.
//

import Cocoa

final class SidebarView: NSView {
    let inspector = DisplayInspectorView()

    private enum Tool: Int, CaseIterable {
        case referenceImage, wallpaper

        var title: String {
            switch self {
            case .referenceImage: return "Reference Image"
            case .wallpaper: return "Wallpaper"
            }
        }

        var summary: String {
            switch self {
            case .referenceImage:
                return ""
            case .wallpaper:
                return "Span one image across all displays and export a version for each screen."
            }
        }
    }

    private let toolsContainer = NSView()
    private let tabs = NSSegmentedControl(labels: Tool.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    let referenceImagePanel = ReferenceImagePanel()
    private lazy var panels: [Tool: NSView] = [
        .referenceImage: referenceImagePanel,
        .wallpaper: ToolPlaceholderView(title: Tool.wallpaper.title, summary: Tool.wallpaper.summary)
    ]

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    /// Show the inspector when a display is selected, the tool tabs otherwise.
    func setDisplaySelected(_ selected: Bool) {
        inspector.isHidden = !selected
        toolsContainer.isHidden = selected
    }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        tabs.selectedSegment = 0
        tabs.target = self
        tabs.action = #selector(tabChanged)
        tabs.translatesAutoresizingMaskIntoConstraints = false
        toolsContainer.translatesAutoresizingMaskIntoConstraints = false
        toolsContainer.addSubview(tabs)

        for panel in panels.values {
            panel.translatesAutoresizingMaskIntoConstraints = false
            toolsContainer.addSubview(panel)
            NSLayoutConstraint.activate([
                panel.leadingAnchor.constraint(equalTo: toolsContainer.leadingAnchor),
                panel.trailingAnchor.constraint(equalTo: toolsContainer.trailingAnchor),
                panel.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8),
                panel.bottomAnchor.constraint(equalTo: toolsContainer.bottomAnchor)
            ])
        }
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: toolsContainer.topAnchor, constant: 14),
            tabs.leadingAnchor.constraint(equalTo: toolsContainer.leadingAnchor, constant: 14),
            tabs.trailingAnchor.constraint(equalTo: toolsContainer.trailingAnchor, constant: -14)
        ])

        for child in [toolsContainer, inspector] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: leadingAnchor),
                child.trailingAnchor.constraint(equalTo: trailingAnchor),
                child.topAnchor.constraint(equalTo: topAnchor),
                child.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        tabChanged()
        setDisplaySelected(false)
    }

    @objc private func tabChanged() {
        let current = Tool(rawValue: tabs.selectedSegment)
        for (tool, panel) in panels { panel.isHidden = tool != current }
    }
}

/// Stand-in for a tool panel that hasn't been built yet.
private final class ToolPlaceholderView: NSView {
    init(title: String, summary: String) {
        super.init(frame: .zero)
        let heading = NSTextField(labelWithString: title)
        heading.font = .boldSystemFont(ofSize: 16)
        let body = NSTextField(wrappingLabelWithString: summary)
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        let note = NSTextField(labelWithString: "Coming soon")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        let stack = NSStackView(views: [heading, body, note])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
