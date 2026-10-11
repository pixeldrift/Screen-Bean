//
//  ImageLayerPanel.swift
//  ScreenBean
//
//  Sidebar options for one workspace image layer (reference image or spanned
//  wallpaper): choose or drop a file, preview it, and set how it blends with
//  the displays. The reference image also gets position and scale fields.
//

import Cocoa
import UniformTypeIdentifiers

final class ImageLayerPanel: NSView {
    /// Called with the chosen image and its original file bytes (both nil when cleared).
    var onImageChanged: ((NSImage?, Data?) -> Void)?
    /// Called with a blend value from -1 to 1. See `ImageLayerBlend`.
    var onBlendChanged: ((Double) -> Void)?
    /// Called when the lock button is clicked.
    var onLockChanged: ((Bool) -> Void)?
    /// Called when the clip-to-displays checkbox changes (wallpaper only).
    var onClipChanged: ((Bool) -> Void)?
    /// Called when the user edits the position or scale fields.
    var onFrameChanged: ((ImageFrame) -> Void)?

    private let dropZone = ImageDropView()
    private let chooseButton = DropButton(title: "Choose Image…", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let slider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    private let readout = NSTextField(labelWithString: "")
    private let x = NumberInput(), y = NumberInput(), width = NumberInput(), height = NumberInput(), rotation = NumberInput()
    private var transformSection: NSView?
    /// Controls that only make sense once there is an image to apply them to.
    private var imageOnlyViews: [NSView] = []
    private let lockButton = NSButton()
    private var isLocked = false
    private let clipCheckbox = NSButton(checkboxWithTitle: "Preview clipped to displays", target: nil, action: nil)

    private let titleText: String
    private let showsTransform: Bool
    private let showsClipToggle: Bool
    private var frameValue: ImageFrame?

    /// Height / width of the current image; 1 when there is none.
    private var aspect: Double {
        guard let size = dropZone.image?.size, size.width > 0 else { return 1 }
        return Double(size.height / size.width)
    }

    init(title: String, showsTransform: Bool = false, showsClipToggle: Bool = false) {
        titleText = title
        self.showsTransform = showsTransform
        self.showsClipToggle = showsClipToggle
        super.init(frame: .zero)
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows saved state without notifying the change callbacks.
    func restore(image: NSImage?, blend: Double) {
        dropZone.image = image
        clearButton.isEnabled = image != nil
        slider.isEnabled = image != nil
        lockButton.isEnabled = image != nil
        slider.doubleValue = blend
        updateReadout()
        updateImageControlsVisibility()
    }

    /// Shows the lock state without notifying `onLockChanged`. A locked image's position fields are read-only.
    func setLocked(_ locked: Bool) {
        isLocked = locked
        lockButton.image = NSImage(systemSymbolName: locked ? "lock.fill" : "lock.open", accessibilityDescription: locked ? "Unlock image" : "Lock image")
        lockButton.contentTintColor = locked ? .labelColor : .secondaryLabelColor
        lockButton.toolTip = locked ? "Locked – click to allow moving and scaling" : "Lock this image's position and scale"
        for input in [x, y, width, height, rotation] { input.isEnabled = !locked }
    }

    /// Shows the saved clip setting without notifying `onClipChanged`.
    func restoreClip(_ clipped: Bool) { clipCheckbox.state = clipped ? .on : .off }

    /// Shows the image's current position and size, without notifying `onFrameChanged`.
    func showFrame(_ frame: ImageFrame?) {
        frameValue = frame
        guard let frame else { return }
        x.value = frame.centerX; y.value = frame.centerY
        width.value = frame.width; height.value = frame.width * aspect
        rotation.value = frame.rotation
    }

    private func build() {
        let title = NSTextField(labelWithString: titleText)
        title.font = .boldSystemFont(ofSize: 14)

        dropZone.translatesAutoresizingMaskIntoConstraints = false
        dropZone.heightAnchor.constraint(equalToConstant: 90).isActive = true
        dropZone.onClick = { [weak self] in self?.chooseImage() }
        dropZone.onDropURL = { [weak self] in self?.load(url: $0) }

        chooseButton.target = self; chooseButton.action = #selector(chooseImage)
        chooseButton.onDropURL = { [weak self] in self?.load(url: $0) }
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

        lockButton.isBordered = false
        lockButton.imageScaling = .scaleProportionallyUpOrDown
        lockButton.target = self; lockButton.action = #selector(lockToggled)
        lockButton.widthAnchor.constraint(equalToConstant: 18).isActive = true
        lockButton.heightAnchor.constraint(equalToConstant: 18).isActive = true
        setLocked(false)
        let header = NSStackView(views: [title, NSView(), lockButton])
        header.distribution = .fill

        // Image first, then how it blends, then (for images) where it sits and how big it is.
        var views: [NSView] = [header, dropZone, buttons, heading, sliderHolder, ends, readout]
        imageOnlyViews = [heading, sliderHolder, ends, readout, lockButton]
        if showsClipToggle {
            clipCheckbox.target = self; clipCheckbox.action = #selector(clipToggled)
            views.append(clipCheckbox)
            imageOnlyViews.append(clipCheckbox)
        }
        if showsTransform {
            let section = buildTransformSection()
            transformSection = section
            views.append(section)
            imageOnlyViews.append(section)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        var fullWidth: [NSView] = [header, dropZone, sliderHolder, ends]
        if let transformSection { fullWidth.append(transformSection) }
        for v in fullWidth { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateReadout()
        updateImageControlsVisibility()
    }

    private func buildTransformSection() -> NSView {
        for input in [x, y, width, height] { input.step = 0.1 }
        x.minimum = -100000; y.minimum = -100000
        width.minimum = 0.1; height.minimum = 0.1
        // Angles are plain decimals, never fractions of an inch.
        rotation.isMeasurement = false
        rotation.minimum = -360
        rotation.step = 1
        rotation.onChange = { [weak self] v in self?.edit { $0.rotation = ImageFrame.normalized(v) } }
        x.onChange = { [weak self] v in self?.edit { $0.centerX = v } }
        y.onChange = { [weak self] v in self?.edit { $0.centerY = v } }
        width.onChange = { [weak self] v in self?.edit { $0.width = v } }
        height.onChange = { [weak self] v in
            guard let self else { return }
            let aspect = self.aspect
            self.edit { $0.width = v / aspect }
        }
        let section = NSStackView(views: [
            twoColumnGrid(x.labeled("X-Pos", unit: "inches"), y.labeled("Y-Pos", unit: "inches")),
            twoColumnGrid(width.labeled("Width", unit: "inches"), height.labeled("Height", unit: "inches")),
            twoColumnGrid(rotation.labeled("Rotation", unit: "degrees"), NSView())
        ])
        section.orientation = .vertical; section.alignment = .width; section.spacing = 8
        return section
    }

    private func edit(_ change: (inout ImageFrame) -> Void) {
        guard var frame = frameValue else { return }
        change(&frame)
        showFrame(frame)
        onFrameChanged?(frame)
    }

    private func updateImageControlsVisibility() {
        let hasImage = dropZone.image != nil
        for view in imageOnlyViews { view.isHidden = !hasImage }
    }

    // MARK: - Actions

    @objc private func chooseImage() {
        let open = NSOpenPanel()
        open.allowedContentTypes = [.image]
        open.allowsMultipleSelection = false
        open.canChooseDirectories = false
        guard open.runModal() == .OK, let url = open.url else { return }
        load(url: url)
    }

    private func load(url: URL) {
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return }
        setImage(image)
        onImageChanged?(image, data)
    }

    @objc private func clearImage() {
        setImage(nil)
        onImageChanged?(nil, nil)
    }

    private func setImage(_ image: NSImage?) {
        dropZone.image = image
        clearButton.isEnabled = image != nil
        slider.isEnabled = image != nil
        lockButton.isEnabled = image != nil
        // Make a freshly chosen image visible, sitting below the displays.
        if image != nil, slider.doubleValue == 0 { slider.doubleValue = -1; onBlendChanged?(-1) }
        updateReadout()
        updateImageControlsVisibility()
    }

    @objc private func lockToggled() {
        setLocked(!isLocked)
        onLockChanged?(isLocked)
    }

    @objc private func clipToggled() { onClipChanged?(clipCheckbox.state == .on) }

    @objc private func sliderChanged() {
        // A detent at zero (invisible) makes it easy to land on.
        if abs(slider.doubleValue) < 0.04 { slider.doubleValue = 0 }
        updateReadout()
        onBlendChanged?(slider.doubleValue)
    }

    private func updateReadout() {
        let blend = ImageLayerBlend(value: slider.doubleValue)
        if dropZone.image == nil { readout.stringValue = "" }
        else if blend.opacity == 0 { readout.stringValue = "Hidden" }
        else { readout.stringValue = "\(Int((blend.opacity * 100).rounded()))% opacity, \(blend.aboveDisplays ? "above" : "below") displays" }
    }
}

/// Interprets the image layer slider: -1 is the image below the displays at
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
