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
    let referenceImagePanel = ImageLayerPanel(title: "Reference Image")
    let wallpaperPanel = ImageLayerPanel(title: "Spanned Wallpaper")
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
        toolsContainer.translatesAutoresizingMaskIntoConstraints = false
        toolsContainer.addSubview(stack)
        for v in [referenceImagePanel, divider, wallpaperPanel] { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: toolsContainer.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: toolsContainer.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: toolsContainer.topAnchor, constant: 18)
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
