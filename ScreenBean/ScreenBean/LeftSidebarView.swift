//
//  LeftSidebarView.swift
//  ScreenBean
//
//  The sidebar on the left: every display in the layout, with buttons to refresh them from macOS
//  and to add a virtual one. It collapses to a thin strip.
//

import Cocoa

final class LeftSidebarView: NSView {
    static let expandedWidth: CGFloat = 230
    static let collapsedWidth: CGFloat = 34
    private static let collapsedKey = "ScreenBean.DisplaysSidebarCollapsed"

    let displaysPanel = DisplaysPanel()
    let refreshButton = NSButton(title: "Refresh Displays", target: nil, action: nil)
    let addVirtualButton = NSButton(title: "Add Virtual Display…", target: nil, action: nil)
    let settingsButton = NSButton(title: "System Settings…", target: nil, action: nil)

    private let content = NSView()
    private let expandButton = NSButton()
    private var widthConstraint: NSLayoutConstraint!

    private(set) var isCollapsed: Bool {
        get { UserDefaults.standard.bool(forKey: Self.collapsedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.collapsedKey) }
    }

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        widthConstraint = widthAnchor.constraint(equalToConstant: Self.expandedWidth)
        widthConstraint.isActive = true

        // A thin line on the right edge, between the sidebar and the workspace.
        let edge = NSBox(); edge.boxType = .separator
        edge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(edge)

        // The list scrolls; the buttons stay at the bottom.
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        displaysPanel.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(displaysPanel)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // Each button fills the sidebar's width and carries an icon.
        let icons: [(NSButton, String)] = [(refreshButton, "arrow.clockwise"), (addVirtualButton, "plus.square.dashed"), (settingsButton, "gearshape")]
        for (button, symbol) in icons {
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: button.title)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
        }
        settingsButton.toolTip = "Open Displays in System Settings"
        refreshButton.toolTip = "Read the displays from macOS again, for example after changing them in System Settings"
        addVirtualButton.toolTip = "Add a planned display that isn't connected"
        let buttons = NSStackView(views: [refreshButton, addVirtualButton, settingsButton])
        buttons.orientation = .vertical; buttons.alignment = .width; buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll); content.addSubview(buttons)
        addSubview(content)

        expandButton.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Show displays")
        expandButton.isBordered = false
        expandButton.contentTintColor = .secondaryLabelColor
        expandButton.toolTip = "Show the displays sidebar"
        expandButton.target = self; expandButton.action = #selector(toggleCollapsed)
        expandButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(expandButton)
        displaysPanel.onCollapse = { [weak self] in self?.toggleCollapsed() }

        NSLayoutConstraint.activate([
            edge.topAnchor.constraint(equalTo: topAnchor),
            edge.bottomAnchor.constraint(equalTo: bottomAnchor),
            edge.trailingAnchor.constraint(equalTo: trailingAnchor),
            edge.widthAnchor.constraint(equalToConstant: 1),

            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            // The contents keep their expanded width even while the sidebar is collapsed (and hidden).
            content.widthAnchor.constraint(equalToConstant: Self.expandedWidth - 1),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),

            displaysPanel.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 14),
            displaysPanel.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -14),
            displaysPanel.topAnchor.constraint(equalTo: document.topAnchor, constant: 18),
            displaysPanel.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -18),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -8),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),

            expandButton.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -0.5),
            expandButton.topAnchor.constraint(equalTo: topAnchor, constant: 18)
        ])
        applyCollapsed()
    }

    private func applyCollapsed() {
        widthConstraint.constant = isCollapsed ? Self.collapsedWidth : Self.expandedWidth
        content.isHidden = isCollapsed
        expandButton.isHidden = !isCollapsed
    }

    @objc private func toggleCollapsed() {
        isCollapsed.toggle()
        applyCollapsed()
    }
}
