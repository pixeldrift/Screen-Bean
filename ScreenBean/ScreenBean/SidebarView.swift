//
//  SidebarView.swift
//  ScreenBean
//
//  Right-hand sidebar. Shows the display inspector while a display is
//  selected; otherwise shows the workspace-wide image tools.
//

import Cocoa

final class SidebarView: NSView {
    let inspector = DisplayInspectorView()
    let referenceImagePanel = ImageLayerPanel(title: "Reference Image", showsTransform: true)
    let wallpaperPanel = ImageLayerPanel(title: "Spanned Wallpaper", showsTransform: true, showsClipToggle: true)
    let exportImagesButton = NSButton(title: "Export Images", target: nil, action: nil)
    let applyWallpaperButton = NSButton(title: "Apply Wallpaper", target: nil, action: nil)

    private let toolsContainer = NSView()

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    /// Show the inspector when a display is selected, the image tools otherwise.
    func setDisplaySelected(_ selected: Bool) {
        inspector.isHidden = !selected
        toolsContainer.isHidden = selected
    }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let divider = NSBox(); divider.boxType = .separator
        let buttons = NSStackView(views: [exportImagesButton, applyWallpaperButton])
        buttons.spacing = 8

        let stack = NSStackView(views: [referenceImagePanel, divider, wallpaperPanel, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        for v in [referenceImagePanel, divider, wallpaperPanel] { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }

        // The tools are taller than a short window, so they scroll.
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false
        toolsContainer.translatesAutoresizingMaskIntoConstraints = false
        toolsContainer.addSubview(scroll)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -18),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            scroll.leadingAnchor.constraint(equalTo: toolsContainer.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: toolsContainer.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: toolsContainer.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: toolsContainer.bottomAnchor)
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
        setDisplaySelected(false)
    }
}
