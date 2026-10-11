//
//  ImageLayerPanel.swift
//  ScreenBean
//
//  Sidebar options for one workspace image layer (reference image or spanned
//  wallpaper): choose a file, preview it, and set how it blends with the displays.
//

import Cocoa
import UniformTypeIdentifiers

final class ImageLayerPanel: NSView {
    /// Called with the chosen image and its original file bytes (both nil when cleared).
    var onImageChanged: ((NSImage?, Data?) -> Void)?
    /// Called with a blend value from -1 to 1. See `ImageLayerBlend`.
    var onBlendChanged: ((Double) -> Void)?

    private let thumbnail = NSImageView()
    private let chooseButton = NSButton(title: "Choose Image…", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let slider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    private let readout = NSTextField(labelWithString: "")

    private let titleText: String

    init(title: String) {
        titleText = title
        super.init(frame: .zero)
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows saved state without notifying `onImageChanged` / `onBlendChanged`.
    func restore(image: NSImage?, blend: Double) {
        thumbnail.image = image
        clearButton.isEnabled = image != nil
        slider.isEnabled = image != nil
        slider.doubleValue = blend
        updateReadout()
    }

    private func build() {
        let title = NSTextField(labelWithString: titleText)
        title.font = .boldSystemFont(ofSize: 14)

        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.imageFrameStyle = .grayBezel
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        thumbnail.heightAnchor.constraint(equalToConstant: 140).isActive = true

        chooseButton.target = self; chooseButton.action = #selector(chooseImage)
        clearButton.target = self; clearButton.action = #selector(clearImage)
        clearButton.isEnabled = false
        let buttons = NSStackView(views: [chooseButton, clearButton])
        buttons.spacing = 8

        slider.target = self; slider.action = #selector(sliderChanged)
        slider.isEnabled = false
        slider.translatesAutoresizingMaskIntoConstraints = false

        // Tick mark at the center, where the image is fully transparent.
        let tick = NSBox(); tick.boxType = .separator
        tick.translatesAutoresizingMaskIntoConstraints = false
        let sliderHolder = NSView()
        sliderHolder.translatesAutoresizingMaskIntoConstraints = false
        sliderHolder.addSubview(tick); sliderHolder.addSubview(slider)
        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: sliderHolder.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: sliderHolder.trailingAnchor),
            slider.centerYAnchor.constraint(equalTo: sliderHolder.centerYAnchor),
            tick.centerXAnchor.constraint(equalTo: slider.centerXAnchor),
            tick.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            tick.widthAnchor.constraint(equalToConstant: 1),
            tick.heightAnchor.constraint(equalToConstant: 16),
            sliderHolder.heightAnchor.constraint(equalToConstant: 24)
        ])

        let below = NSTextField(labelWithString: "Below")
        let above = NSTextField(labelWithString: "Above")
        let spacer = NSView()
        for l in [below, above] { l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor }
        let ends = NSStackView(views: [below, spacer, above])
        ends.distribution = .fill
        readout.font = .systemFont(ofSize: 11); readout.textColor = .secondaryLabelColor

        let heading = NSTextField(labelWithString: "OPACITY & LAYER")
        heading.font = .boldSystemFont(ofSize: 10); heading.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, thumbnail, buttons, heading, sliderHolder, ends, readout])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for v in [thumbnail, sliderHolder, ends] { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateReadout()
    }

    @objc private func chooseImage() {
        let open = NSOpenPanel()
        open.allowedContentTypes = [.image]
        open.allowsMultipleSelection = false
        open.canChooseDirectories = false
        guard open.runModal() == .OK, let url = open.url,
              let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return }
        setImage(image)
        onImageChanged?(image, data)
    }

    @objc private func clearImage() {
        setImage(nil)
        onImageChanged?(nil, nil)
    }

    private func setImage(_ image: NSImage?) {
        thumbnail.image = image
        clearButton.isEnabled = image != nil
        slider.isEnabled = image != nil
        // Make a freshly chosen image visible, sitting below the displays.
        if image != nil, slider.doubleValue == 0 { slider.doubleValue = -1; onBlendChanged?(-1) }
        updateReadout()
    }

    @objc private func sliderChanged() {
        updateReadout()
        onBlendChanged?(slider.doubleValue)
    }

    private func updateReadout() {
        let blend = ImageLayerBlend(value: slider.doubleValue)
        if thumbnail.image == nil { readout.stringValue = "No image chosen" }
        else if blend.opacity == 0 { readout.stringValue = "Hidden" }
        else { readout.stringValue = "\(Int((blend.opacity * 100).rounded()))% opacity, \(blend.aboveDisplays ? "above" : "below") displays" }
    }
}

/// Interprets the reference image slider: -1 is the image below the displays at
/// full opacity, 0 is invisible, and +1 is the image above the displays at full opacity.
struct ImageLayerBlend {
    var opacity: Double
    var aboveDisplays: Bool

    init(value: Double) {
        let v = min(max(value, -1), 1)
        opacity = abs(v)
        aboveDisplays = v > 0
    }
}
