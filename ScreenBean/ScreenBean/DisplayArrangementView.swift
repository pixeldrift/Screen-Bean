//
//  DisplayArrangementView.swift
//  ScreenBean
//
import Cocoa

class DisplayArrangementView: NSView {
    private var suppressDisplayRebuild = false
    var displays: [DisplayInfo] = [] {
        didSet {
            if !suppressDisplayRebuild { rebuildPhysicalLayout() }
            needsLayout = true
            needsDisplay = true
        }
    }

    /// The display currently selected in the workspace.
    private(set) var selectedDisplayID: CGDirectDisplayID?

    /// Notifies the app when workspace selection changes.
    var onSelectionChanged: ((DisplayInfo?) -> Void)?
    var onDisplayValuesChanged: ((DisplayInfo?, CGFloat, CGFloat) -> Void)?

    private var physicalLayout = PhysicalLayout()

    /// An image drawn in the workspace. Its blend sets the opacity and whether it
    /// draws below or above the displays. A layer with a frame sits at that spot in
    /// the workspace; one without is sized to the width of the arrangement.
    struct ImageLayer {
        var image: NSImage?
        var blend = ImageLayerBlend(value: 0)
        var frame: ImageFrame?
        /// A locked image can't be moved or scaled.
        var isLocked = false
    }

    /// Photo or plan drawn as a layout reference, independent of the displays.
    var referenceLayer = ImageLayer() { didSet { layerDidChange(.referenceImage) } }
    /// One image spanned across the whole arrangement.
    var wallpaperLayer = ImageLayer() { didSet { layerDidChange(.wallpaper) } }
    /// When on, the wallpaper only shows where it overlaps a display.
    var wallpaperClipsToDisplays = false { didSet { needsDisplay = true } }
    /// Called when an image is moved or scaled in the workspace, or its frame is created or cleared.
    var onImageFrameChanged: ((ImageLayerSlot, ImageFrame?) -> Void)?
    /// Called when an image is locked or unlocked from its on-canvas lock icon.
    var onImageLockChanged: ((ImageLayerSlot, Bool) -> Void)?

    /// Image layers from back to front.
    private let imageSlots: [ImageLayerSlot] = [.referenceImage, .wallpaper]

    private func layer(_ slot: ImageLayerSlot) -> ImageLayer {
        slot == .referenceImage ? referenceLayer : wallpaperLayer
    }

    /// Whether an image draws over the displays. A wallpaper previewed clipped to the
    /// displays always does, since it would otherwise be hidden behind them.
    private func drawsAboveDisplays(_ slot: ImageLayerSlot) -> Bool {
        layer(slot).blend.aboveDisplays || (slot == .wallpaper && wallpaperClipsToDisplays)
    }

    private func setFrame(_ frame: ImageFrame?, for slot: ImageLayerSlot) {
        if slot == .referenceImage { referenceLayer.frame = frame } else { wallpaperLayer.frame = frame }
    }

    /// Gives a new image a starting frame and drops the frame and selection of a removed one.
    private func layerDidChange(_ slot: ImageLayerSlot) {
        let current = layer(slot)
        if current.image == nil {
            if current.frame != nil {
                setFrame(nil, for: slot)
                onImageFrameChanged?(slot, nil)
            }
            if selectedImage == slot { selectedImage = nil }
        } else if current.frame == nil {
            let frame = defaultFrame(for: slot)
            setFrame(frame, for: slot)
            onImageFrameChanged?(slot, frame)
        }
        needsDisplay = true
    }

    // MARK: - Workspace Camera
    /// Number of view points used to represent one physical inch
    /// at the default zoom level.
    private let basePointsPerInch: CGFloat = 20.0
    /// Current workspace zoom.
    private var zoom: CGFloat = 0.5
    /// Workspace position in view coordinates.
    private var viewOffset = CGPoint.zero
    /// Used while panning the workspace.
    private var panStartPoint = CGPoint.zero
    private var panStartOffset = CGPoint.zero
    private var isPanning = false
    /// A custom guide being dragged out of a ruler, or moved.
    private var guideDrag: UUID?
    private var hoverGuideID: UUID?
    private var guideDragPoint = CGPoint.zero
    /// Shift-dragging the background zooms around the point where the drag began.
    private var isZoomDragging = false
    private var zoomDragStart = CGPoint.zero
    private var zoomDragStartZoom: CGFloat = 1
    private var zoomDragAnchor = CGPoint.zero
    // Selection, hover and drag state for displays and the reference image.
    private var selectedImage: ImageLayerSlot?
    private var hoverTarget: EditTarget?
    private var dragTarget: EditTarget?
    private var dragMode = DragMode.move
    private var dragStartPoint = CGPoint.zero
    private var dragStartRect = CGRect.zero
    private var hasInitializedView = false
    private var lastLayoutSize = CGSize.zero
    

    
    // MARK: - Setup

    /// Something in the workspace that can be moved and resized.
    private enum EditTarget: Equatable {
        case display(CGDirectDisplayID)
        case image(ImageLayerSlot)
    }

    private enum DragMode {
        case move
        case resize(GrabHandle)
    }

    /// The eight dots around a selected or hovered item.
    private enum GrabHandle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        /// Position along the item's width and height, from 0 (min) to 1 (max).
        var unit: CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: 0, y: 1)
            case .top: return CGPoint(x: 0.5, y: 1)
            case .topRight: return CGPoint(x: 1, y: 1)
            case .right: return CGPoint(x: 1, y: 0.5)
            case .bottomRight: return CGPoint(x: 1, y: 0)
            case .bottom: return CGPoint(x: 0.5, y: 0)
            case .bottomLeft: return CGPoint(x: 0, y: 0)
            case .left: return CGPoint(x: 0, y: 0.5)
            }
        }

        var isCorner: Bool { unit.x != 0.5 && unit.y != 0.5 }
    }

    private let cornerHandleRadius: CGFloat = 6
    private let edgeHandleRadius: CGFloat = 4
    private let minimumItemSize: CGFloat = 0.5

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    private var settingsObservers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Redraw when settings that change how displays look are switched.
        guard settingsObservers.isEmpty else { return }
        for name in [BezelVisibility.didChange, MeasurementFormat.didChange, GuideSettings.didChange, GuideStore.didChange] {
            settingsObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.needsDisplay = true
            })
        }
    }

    override func layout() {
        super.layout()

        guard !displays.isEmpty,
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }

        if !hasInitializedView {
            hasInitializedView = true
            lastLayoutSize = bounds.size
            zoomToFit(initialZoomFactor: 0.5)
            return
        }

        if bounds.size != lastLayoutSize {
            lastLayoutSize = bounds.size
            centerView()
        }
    }

    // MARK: - Layout
    private func rebuildPhysicalLayout() {
        guard !displays.isEmpty else {
            physicalLayout = PhysicalLayout()
            return
        }

        var physicalDisplays: [PhysicalLayout.Display] = []

        let referenceDisplay = displays[0]

        let referencePixelWidth =
            max(
                CGFloat(referenceDisplay.pixelWidth),
                1
            )

        let referencePhysicalWidth =
            max(
                CGFloat(referenceDisplay.physicalWidthInches),
                0.1
            )

        let inchesPerMacUnit =
            referencePhysicalWidth /
            referencePixelWidth

        let referenceCenterX =
            CGFloat(referenceDisplay.positionX) +
            CGFloat(referenceDisplay.pixelWidth) / 2

        let referenceCenterY =
            CGFloat(referenceDisplay.positionY) +
            CGFloat(referenceDisplay.pixelHeight) / 2

        for display in displays {
            let pixelX =
                CGFloat(display.positionX)

            let pixelY =
                CGFloat(display.positionY)

            let physicalWidth =
                CGFloat(display.physicalWidthInches)

            let physicalHeight =
                CGFloat(display.physicalHeightInches)

            // macOS x grows rightward like the workspace; macOS y grows downward, the workspace's upward.
            let physicalCenterX =
                (pixelX - referenceCenterX) *
                inchesPerMacUnit

            let physicalCenterY =
                -(pixelY - referenceCenterY) *
                inchesPerMacUnit

            let physicalX =
                physicalCenterX -
                physicalWidth / 2

            let physicalY =
                physicalCenterY -
                physicalHeight / 2

            let saved = DisplayConfigurationStore.shared.configuration(for: display.persistentID)
            // A saved position is kept by its center, so a display whose size changed
            // (for example after being rotated) stays where it was.
            var originX = physicalX
            var originY = physicalY
            if let saved {
                originX = CGFloat(saved.xInches + saved.widthInches / 2) - physicalWidth / 2
                originY = CGFloat(saved.yInches + saved.heightInches / 2) - physicalHeight / 2
            }
            let physicalDisplay = PhysicalLayout.Display(
                id: display.displayID, nickname: display.nickname,
                persistentID: display.persistentID, colorHex: display.colorHex,
                uniformBezel: display.uniformBezel,
                bezelUniform: CGFloat(display.bezelUniform), bezelTop: CGFloat(display.bezelTop), bezelBottom: CGFloat(display.bezelBottom),
                bezelLeft: CGFloat(display.bezelLeft), bezelRight: CGFloat(display.bezelRight),
                bezelColorHex: display.bezelColorHex, showBezel: display.showBezel, isLocked: display.isLocked,
                x: originX,
                y: originY,
                width: physicalWidth, height: physicalHeight
            )

            physicalDisplays.append(
                physicalDisplay
            )
        }

        physicalLayout =
            PhysicalLayout(
                displays: physicalDisplays
            )
    }
    
    
    // MARK: - Coordinate Conversion
    private var pointsPerInch: CGFloat {
        basePointsPerInch * zoom
    }
    private func physicalRectToView(
        _ display: PhysicalLayout.Display
    ) -> CGRect {
        let rect =
            physicalLayout.rectInView(
                for: display,
                scale: pointsPerInch
            )
        return rect.offsetBy(
            dx: viewOffset.x,
            dy: viewOffset.y
        )
    }
    
    // MARK: - Drawing
    override func draw(
        _ dirtyRect: NSRect
    ) {
        super.draw(dirtyRect)
        guard let context =
            NSGraphicsContext.current?.cgContext
        else {
            return
        }
        context.clear(bounds)
        drawGrid(
            in: context
        )
        guard !physicalLayout.displays.isEmpty else {
            return
        }
        for slot in imageSlots where !drawsAboveDisplays(slot) { drawImageLayer(slot) }
        for (index, display) in physicalLayout.displays.enumerated() {
            let rect =
                physicalRectToView(
                    display
                )
            drawDisplay(
                display,
                in: context,
                rect: rect,
                isSelected: display.id == selectedDisplayID,
                label: DisplayIdentity.label(forIndex: index)
            )
        }
        for slot in imageSlots where drawsAboveDisplays(slot) { drawImageLayer(slot) }
        drawImageLockIcons(in: context)
        drawGuides()
        var withHandles: [EditTarget] = []
        for target in [currentSelection, hoverTarget].compactMap({ $0 }) where !withHandles.contains(target) {
            withHandles.append(target)
            drawHandles(for: target, in: context)
        }
        drawRulers()
        drawGuideDragLabel()
    }

    // MARK: - Image Layers
    /// Where an image layer sits, in physical inches.
    private func physicalRect(of layer: ImageLayer) -> CGRect? {
        guard let image = layer.image, image.size.width > 0, image.size.height > 0, let frame = layer.frame else { return nil }
        let height = CGFloat(frame.width) * image.size.height / image.size.width
        return CGRect(x: CGFloat(frame.centerX - frame.width / 2), y: CGFloat(frame.centerY) - height / 2, width: CGFloat(frame.width), height: height)
    }

    /// A new image starts centered on the arrangement: the reference image at the
    /// arrangement's width, the wallpaper scaled up to cover the whole arrangement.
    private func defaultFrame(for slot: ImageLayerSlot) -> ImageFrame {
        guard physicalLayout.width > 0, let image = layer(slot).image, image.size.width > 0 else {
            return ImageFrame(centerX: 0, centerY: 0, width: 40)
        }
        var width = physicalLayout.width
        if slot == .wallpaper {
            let aspect = image.size.height / image.size.width
            width = max(width, physicalLayout.height / aspect)
        }
        return ImageFrame(
            centerX: Double((physicalLayout.minX + physicalLayout.maxX) / 2),
            centerY: Double((physicalLayout.minY + physicalLayout.maxY) / 2),
            width: Double(width)
        )
    }

    private func drawImageLayer(_ slot: ImageLayerSlot) {
        let current = layer(slot)
        guard let image = current.image, let physical = physicalRect(of: current) else { return }
        let target = viewRect(forPhysical: physical)
        func drawImage(opacity: CGFloat) {
            image.draw(in: target, from: .zero, operation: .sourceOver, fraction: opacity, respectFlipped: true, hints: nil)
        }

        if slot == .wallpaper && wallpaperClipsToDisplays {
            // Full strength on the displays; the slider's opacity everywhere else.
            let screens = NSBezierPath()
            for display in physicalLayout.displays { screens.appendRect(physicalRectToView(display)) }
            if current.blend.opacity > 0 {
                NSGraphicsContext.saveGraphicsState()
                let outside = NSBezierPath(rect: bounds)
                outside.append(screens)
                outside.windingRule = .evenOdd
                outside.addClip()
                drawImage(opacity: CGFloat(current.blend.opacity))
                NSGraphicsContext.restoreGraphicsState()
            }
            NSGraphicsContext.saveGraphicsState()
            screens.addClip()
            drawImage(opacity: 1)
            NSGraphicsContext.restoreGraphicsState()
        } else if current.blend.opacity > 0 {
            drawImage(opacity: CGFloat(current.blend.opacity))
        }
    }

    // MARK: - Grid
    private func drawGrid(
        in context: CGContext
    ) {
        let gridSpacingInches: CGFloat = 1.0
        let spacing =
            gridSpacingInches * pointsPerInch

        guard spacing > 2 else {
            return
        }

        let originX = viewOffset.x
        let originY = viewOffset.y

        context.saveGState()

        // Grid
        context.setStrokeColor(
            NSColor.separatorColor
                .withAlphaComponent(0.05)
                .cgColor
        )

        context.setLineWidth(1)

        var x = originX

        while x > 0 {
            x -= spacing
        }

        while x < bounds.width {
            context.move(
                to: CGPoint(x: x, y: 0)
            )

            context.addLine(
                to: CGPoint(
                    x: x,
                    y: bounds.height
                )
            )

            x += spacing
        }

        var y = originY

        while y > 0 {
            y -= spacing
        }

        while y < bounds.height {
            context.move(
                to: CGPoint(x: 0, y: y)
            )

            context.addLine(
                to: CGPoint(
                    x: bounds.width,
                    y: y
                )
            )

            y += spacing
        }

        context.strokePath()

        // Cartesian axes
        context.setStrokeColor(
            NSColor.labelColor
                .withAlphaComponent(0.25)
                .cgColor
        )

        context.setLineWidth(2)

        context.move(
            to: CGPoint(
                x: originX,
                y: 0
            )
        )

        context.addLine(
            to: CGPoint(
                x: originX,
                y: bounds.height
            )
        )

        context.move(
            to: CGPoint(
                x: 0,
                y: originY
            )
        )

        context.addLine(
            to: CGPoint(
                x: bounds.width,
                y: originY
            )
        )

        context.strokePath()

        context.restoreGState()
    }
    
    // MARK: - Display Drawing
    private func drawDisplay(
        _ display: PhysicalLayout.Display,
        in context: CGContext,
        rect: CGRect,
        isSelected: Bool,
        label: String
    ) {
        // Bezel thickness is stored in physical inches and scales with the canvas.
        let scale = pointsPerInch
        let insets = bezelInsets(display)
        let top = insets.top * scale, bottom = insets.bottom * scale
        let left = insets.left * scale, right = insets.right * scale
        let outerRect = CGRect(
            x: rect.minX - left,
            y: rect.minY - bottom,
            width: rect.width + left + right,
            height: rect.height + top + bottom
        )
        let bezelColor = NSColor(displayHex: display.bezelColorHex)
        let frameColor = bezelColor

        // Draw shadow first so it falls outside the monitor's physical frame.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -6 * max(zoom, 0.5)),
            blur: max(10, 26 * zoom),
            color: NSColor.black.withAlphaComponent(0.65).cgColor
        )
        context.setFillColor(frameColor.cgColor)
        context.fill(outerRect)
        context.restoreGState()

        // Bezel frame: a soft top-to-bottom gradient with a raised bevel edge.
        if BezelVisibility.isShown(displaySetting: display.showBezel), let frameGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [(bezelColor.blended(withFraction: 0.13, of: .white) ?? bezelColor).cgColor, (bezelColor.blended(withFraction: 0.31, of: .black) ?? bezelColor).cgColor] as CFArray,
            locations: [0, 1]
        ) {
            context.saveGState()
            context.addRect(outerRect)
            context.clip()
            context.drawLinearGradient(
                frameGradient,
                start: CGPoint(x: outerRect.midX, y: outerRect.maxY),
                end: CGPoint(x: outerRect.midX, y: outerRect.minY),
                options: []
            )
            context.restoreGState()
            drawBevel(in: context, rect: outerRect, raised: true, width: 1.5)
        } else {
            context.setFillColor(frameColor.cgColor)
            context.fill(outerRect)
        }

        let baseColor = NSColor(displayHex: display.colorHex)
        if let gradient = DisplayGradient.make(hex: display.colorHex) {
            context.saveGState()
            context.addRect(rect)
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.maxX, y: rect.maxY),
                end: CGPoint(x: rect.minX, y: rect.minY),
                options: []
            )
            context.restoreGState()
        } else {
            context.setFillColor(baseColor.cgColor)
            context.fill(rect)
        }

        // The panel sits slightly recessed into the frame.
        drawBevel(in: context, rect: rect, raised: false, width: 2)

        drawLockIcon(for: display, in: rect, isSelected: isSelected)

        drawIdentity(of: display, label: label, in: rect)
    }

    /// A faint circle with the display's letter in the middle, and its name,
    /// resolution and physical size in the lower quarter.
    private func drawIdentity(of display: PhysicalLayout.Display, label: String, in rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let diameter = min(rect.width, rect.height) * 0.5
        let circle = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        NSColor.white.withAlphaComponent(0.32).setFill()
        NSBezierPath(ovalIn: circle).fill()

        let ink = NSColor.black.withAlphaComponent(0.7)
        if diameter >= 14 {
            let letterAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: diameter * 0.62, weight: .bold), .foregroundColor: ink]
            let letterSize = (label as NSString).size(withAttributes: letterAttributes)
            (label as NSString).draw(
                at: CGPoint(x: center.x - letterSize.width / 2, y: center.y - letterSize.height / 2),
                withAttributes: letterAttributes
            )
        }

        // Name, then resolution, then size; whatever doesn't fit in the lower quarter is dropped, last line first.
        let info = displays.first(where: { $0.displayID == display.id })
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        func attributes(_ size: CGFloat, weight: NSFont.Weight) -> [NSAttributedString.Key: Any] {
            [.font: NSFont.systemFont(ofSize: size, weight: weight), .paragraphStyle: paragraph, .foregroundColor: ink]
        }
        let nameSize = min(max(rect.height * 0.055, 9), 15)
        let detailSize = min(max(rect.height * 0.045, 8), 12)
        var lines: [(text: String, attributes: [NSAttributedString.Key: Any])] = [(display.nickname, attributes(nameSize, weight: .semibold))]
        if let info { lines.append(("\(info.pixelWidth) × \(info.pixelHeight) px", attributes(detailSize, weight: .regular))) }
        lines.append(("\(MeasurementFormat.string(Double(display.width))) × \(MeasurementFormat.string(Double(display.height))) in", attributes(detailSize, weight: .regular)))

        let box = CGRect(x: rect.minX + 8, y: rect.minY + 6, width: max(rect.width - 16, 1), height: rect.height / 4 - 6)
        func height(of line: (text: String, attributes: [NSAttributedString.Key: Any])) -> CGFloat {
            ceil((line.text as NSString).boundingRect(with: CGSize(width: box.width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: line.attributes).height)
        }
        while lines.count > 1, lines.reduce(0, { $0 + height(of: $1) }) > box.height { lines.removeLast() }
        guard let first = lines.first, height(of: first) <= box.height else { return }

        var top = box.maxY
        for line in lines {
            let lineHeight = height(of: line)
            (line.text as NSString).draw(
                with: CGRect(x: box.minX, y: top - lineHeight, width: box.width, height: lineHeight),
                options: .usesLineFragmentOrigin,
                attributes: line.attributes
            )
            top -= lineHeight
        }
    }

    /// Light and dark edge lines that make a rectangle look raised or recessed.
    private func drawBevel(in context: CGContext, rect: CGRect, raised: Bool, width: CGFloat) {
        let highlight = NSColor.white.withAlphaComponent(raised ? 0.35 : 0.18).cgColor
        let shade = NSColor.black.withAlphaComponent(raised ? 0.45 : 0.55).cgColor
        let topLeft = raised ? highlight : shade
        let bottomRight = raised ? shade : highlight
        let r = rect.insetBy(dx: width / 2, dy: width / 2)
        context.saveGState()
        context.setLineWidth(width)
        context.setStrokeColor(topLeft)
        context.move(to: CGPoint(x: r.minX, y: r.minY)); context.addLine(to: CGPoint(x: r.minX, y: r.maxY)); context.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        context.strokePath()
        context.setStrokeColor(bottomRight)
        context.move(to: CGPoint(x: r.minX, y: r.minY)); context.addLine(to: CGPoint(x: r.maxX, y: r.minY)); context.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - Display Lock
    private let lockIconSize: CGFloat = 18

    /// Clickable area of the lock icon in the display's top-right corner.
    private func lockIconRect(in rect: CGRect) -> CGRect {
        CGRect(x: rect.maxX - lockIconSize - 8, y: rect.maxY - lockIconSize - 8, width: lockIconSize, height: lockIconSize)
    }

    /// Locked displays always show the lock; unlocked ones show it while selected.
    private func drawLockIcon(for display: PhysicalLayout.Display, in rect: CGRect, isSelected: Bool) {
        guard display.isLocked || isSelected else { return }
        drawLockSymbol(locked: display.isLocked, in: lockIconRect(in: rect))
    }

    private func drawLockSymbol(locked: Bool, in iconRect: CGRect) {
        let name = locked ? "lock.fill" : "lock.open.fill"
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: locked ? "Locked" : "Unlocked")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [NSColor.white.withAlphaComponent(locked ? 0.9 : 0.55)]))
        else { return }
        symbol.draw(in: iconRect)
    }

    /// Lock icon in an image's top-right corner; shown while it is locked or selected.
    private func imageLockIconRect(_ slot: ImageLayerSlot) -> CGRect? {
        let current = layer(slot)
        guard current.blend.opacity > 0, let physical = physicalRect(of: current), (current.isLocked || selectedImage == slot) else { return nil }
        let rect = viewRect(forPhysical: physical)
        return CGRect(x: rect.maxX - lockIconSize - 8, y: rect.maxY - lockIconSize - 8, width: lockIconSize, height: lockIconSize)
    }

    private func drawImageLockIcons(in context: CGContext) {
        for slot in imageSlots {
            guard let icon = imageLockIconRect(slot) else { continue }
            // A dark disc keeps the white icon readable over photos.
            context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
            context.fillEllipse(in: icon.insetBy(dx: -5, dy: -5))
            drawLockSymbol(locked: layer(slot).isLocked, in: icon)
        }
    }

    /// Locks or unlocks an image, e.g. from the sidebar.
    func setImageLocked(_ locked: Bool, for slot: ImageLayerSlot) {
        if slot == .referenceImage { referenceLayer.isLocked = locked } else { wallpaperLayer.isLocked = locked }
    }

    // MARK: - Geometry
    private func viewToPhysical(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - viewOffset.x) / pointsPerInch, y: (point.y - viewOffset.y) / pointsPerInch)
    }

    private func viewRect(forPhysical rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * pointsPerInch + viewOffset.x, y: rect.minY * pointsPerInch + viewOffset.y, width: rect.width * pointsPerInch, height: rect.height * pointsPerInch)
    }

    /// Bezel thickness on each side of a display, in inches.
    private func bezelInsets(_ display: PhysicalLayout.Display) -> (top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat) {
        guard BezelVisibility.isShown(displaySetting: display.showBezel) else { return (0, 0, 0, 0) }
        if display.uniformBezel {
            let all = max(0, display.bezelUniform)
            return (all, all, all, all)
        }
        return (max(0, display.bezelTop), max(0, display.bezelBottom), max(0, display.bezelLeft), max(0, display.bezelRight))
    }

    /// A display's footprint including its bezel, in physical inches.
    private func outerPhysicalRect(_ display: PhysicalLayout.Display) -> CGRect {
        let i = bezelInsets(display)
        return CGRect(x: display.x - i.left, y: display.y - i.bottom, width: display.width + i.left + i.right, height: display.height + i.top + i.bottom)
    }

    private func physicalOuterRect(of target: EditTarget) -> CGRect? {
        switch target {
        case .display(let id):
            return physicalLayout.displays.first(where: { $0.id == id }).map(outerPhysicalRect)
        case .image(let slot):
            return physicalRect(of: layer(slot))
        }
    }

    private func isEditable(_ target: EditTarget) -> Bool {
        switch target {
        case .display(let id): return physicalLayout.displays.first(where: { $0.id == id })?.isLocked == false
        case .image(let slot): return layer(slot).image != nil && !layer(slot).isLocked
        }
    }

    private var currentSelection: EditTarget? {
        if let id = selectedDisplayID { return .display(id) }
        return selectedImage.map { .image($0) }
    }

    /// Targets from front to back, following the reference image's layer setting.
    private func targetsFrontToBack() -> [EditTarget] {
        let displayTargets = physicalLayout.displays.reversed().map { EditTarget.display($0.id) }
        // Displays always win a click over an image, whatever the stacking; images follow in layer order.
        func isShown(_ slot: ImageLayerSlot) -> Bool {
            layer(slot).image != nil && (layer(slot).blend.opacity > 0 || (slot == .wallpaper && wallpaperClipsToDisplays))
        }
        let front = imageSlots.reversed().filter { isShown($0) && drawsAboveDisplays($0) }.map { EditTarget.image($0) }
        let back = imageSlots.reversed().filter { isShown($0) && !drawsAboveDisplays($0) }.map { EditTarget.image($0) }
        return displayTargets + front + back
    }

    // MARK: - Grab Handles
    private func handleCenter(_ handle: GrabHandle, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + handle.unit.x * rect.width, y: rect.minY + handle.unit.y * rect.height)
    }

    private func handle(at point: CGPoint, in rect: CGRect) -> GrabHandle? {
        // Corners first so they win where an edge dot is close by.
        let ordered = GrabHandle.allCases.sorted { $0.isCorner && !$1.isCorner }
        return ordered.first { handle in
            let c = handleCenter(handle, in: rect)
            let r = (handle.isCorner ? cornerHandleRadius : edgeHandleRadius) + 3
            return hypot(point.x - c.x, point.y - c.y) <= r
        }
    }

    private func handleColor(for target: EditTarget) -> NSColor {
        if case .display(let id) = target, let d = physicalLayout.displays.first(where: { $0.id == id }) { return NSColor(displayHex: d.colorHex) }
        return .controlAccentColor
    }

    /// An outline in the item's color with dots at the corners and edge midpoints.
    private func drawHandles(for target: EditTarget, in context: CGContext) {
        guard isEditable(target), let physical = physicalOuterRect(of: target) else { return }
        let rect = viewRect(forPhysical: physical)
        let color = handleColor(for: target)
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2)
        context.stroke(rect)
        for handle in GrabHandle.allCases {
            let c = handleCenter(handle, in: rect)
            let r = handle.isCorner ? cornerHandleRadius : edgeHandleRadius
            let dot = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: dot)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: dot)
        }
        context.restoreGState()
    }

    /// The new rectangle when `handle` is dragged to `point`. Corners keep the
    /// rectangle's proportions; edges stretch one side unless `keepAspect` is set.
    private func resizedRect(_ r: CGRect, handle: GrabHandle, to p: CGPoint, keepAspect: Bool, minSize: CGSize) -> CGRect {
        let u = handle.unit
        // The fixed point opposite the handle.
        let anchor = CGPoint(x: r.minX + (1 - u.x) * r.width, y: r.minY + (1 - u.y) * r.height)
        var w = r.width, h = r.height
        if u.x != 0.5 { w = max(minSize.width, u.x == 0 ? anchor.x - p.x : p.x - anchor.x) }
        if u.y != 0.5 { h = max(minSize.height, u.y == 0 ? anchor.y - p.y : p.y - anchor.y) }
        let aspect = r.width / max(r.height, 0.0001)
        if handle.isCorner {
            let scale = max(w / r.width, h / r.height)
            w = r.width * scale; h = r.height * scale
        } else if keepAspect {
            if u.x != 0.5 { h = w / aspect } else { w = h * aspect }
        }
        let x = u.x == 0 ? anchor.x - w : (u.x == 1 ? anchor.x : r.midX - w / 2)
        let y = u.y == 0 ? anchor.y - h : (u.y == 1 ? anchor.y : r.midY - h / 2)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Hit Testing
    /// What is under `point`: a handle of the selected or hovered item, or an item's body.
    private func itemHit(_ point: CGPoint) -> (target: EditTarget, handle: GrabHandle?)? {
        for target in [currentSelection, hoverTarget].compactMap({ $0 }) where isEditable(target) {
            if let physical = physicalOuterRect(of: target), let handle = handle(at: point, in: viewRect(forPhysical: physical)) {
                return (target, handle)
            }
        }
        for target in targetsFrontToBack() {
            if let physical = physicalOuterRect(of: target), viewRect(forPhysical: physical).contains(point) { return (target, nil) }
        }
        return nil
    }

    /// Like `itemHit`, but forgiving enough to keep handles that hang outside an item's edge visible.
    private func hoverTest(_ point: CGPoint) -> EditTarget? {
        if let hit = itemHit(point) { return hit.target }
        let slop = cornerHandleRadius + 3
        return targetsFrontToBack().first { target in
            guard isEditable(target), let physical = physicalOuterRect(of: target) else { return false }
            return viewRect(forPhysical: physical).insetBy(dx: -slop, dy: -slop).contains(point)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let target = hoverTest(point)
        if target != hoverTarget { hoverTarget = target; needsDisplay = true }

        // Custom guides highlight and show a resize cursor under the mouse.
        let guide = rulerAxis(at: point) == nil ? customGuide(at: point) : nil
        if guide?.id != hoverGuideID {
            hoverGuideID = guide?.id
            needsDisplay = true
        }
        if let guide {
            (guide.axis == .horizontal ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).set()
        } else if let axis = rulerAxis(at: point) {
            (axis == .horizontal ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoverTarget != nil { hoverTarget = nil; needsDisplay = true }
        if hoverGuideID != nil { hoverGuideID = nil; needsDisplay = true }
        NSCursor.arrow.set()
    }

    // MARK: - Guide Editing
    override var acceptsFirstResponder: Bool { true }

    /// Delete or Backspace removes the custom guide under the mouse.
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 51 || event.keyCode == 117), let hoverGuideID {
            GuideStore.shared.remove(hoverGuideID)
            self.hoverGuideID = nil
        } else {
            super.keyDown(with: event)
        }
    }

    private final class GuideMenuPayload: NSObject {
        let axis: GuideAxis?
        let position: Double
        let id: UUID?
        init(axis: GuideAxis? = nil, position: Double = 0, id: UUID? = nil) { self.axis = axis; self.position = position; self.id = id }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()
        if let guide = customGuide(at: point) {
            let item = NSMenuItem(title: "Delete Guide", action: #selector(deleteGuideFromMenu(_:)), keyEquivalent: "")
            item.representedObject = GuideMenuPayload(id: guide.id)
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }
        let location = viewToPhysical(point)
        let horizontal = NSMenuItem(title: "Add Horizontal Guide Here", action: #selector(addGuideFromMenu(_:)), keyEquivalent: "")
        horizontal.representedObject = GuideMenuPayload(axis: .horizontal, position: Double(location.y))
        let vertical = NSMenuItem(title: "Add Vertical Guide Here", action: #selector(addGuideFromMenu(_:)), keyEquivalent: "")
        vertical.representedObject = GuideMenuPayload(axis: .vertical, position: Double(location.x))
        let clear = NSMenuItem(title: "Clear Custom Guides", action: #selector(clearGuidesFromMenu), keyEquivalent: "")
        clear.isEnabled = !GuideStore.shared.guides.isEmpty
        for item in [horizontal, vertical, clear] { item.target = self; menu.addItem(item) }
        return menu
    }

    @objc private func deleteGuideFromMenu(_ sender: NSMenuItem) {
        if let id = (sender.representedObject as? GuideMenuPayload)?.id { GuideStore.shared.remove(id) }
    }

    @objc private func addGuideFromMenu(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? GuideMenuPayload, let axis = payload.axis else { return }
        GuideSettings.showGuides = true
        GuideStore.shared.add(Guide(axis: axis, position: payload.position))
        GuideStore.shared.save()
    }

    @objc private func clearGuidesFromMenu() { GuideStore.shared.removeAll() }

    // MARK: - Guides
    /// Every guide to draw: edge guides from the displays, then custom ones.
    func resolvedGuides() -> [ResolvedGuide] {
        guard GuideSettings.showGuides else { return [] }
        var result: [ResolvedGuide] = []
        if GuideSettings.showEdgeGuides {
            let sources = GuideSettings.edgeScope == .selectedDisplay
                ? physicalLayout.displays.filter { $0.id == selectedDisplayID }
                : physicalLayout.displays
            var seen = Set<String>()
            for display in sources {
                let base = NSColor(displayHex: display.colorHex)
                let color = base.blended(withFraction: 0.4, of: .black) ?? base
                let edges: [(GuideAxis, CGFloat)] = [
                    (.vertical, display.x), (.vertical, display.right),
                    (.horizontal, display.y), (.horizontal, display.bottom)
                ]
                for (axis, position) in edges {
                    // Displays that share an edge share one guide.
                    guard seen.insert("\(axis.rawValue)\(Int((position * 1000).rounded()))").inserted else { continue }
                    result.append(ResolvedGuide(axis: axis, position: Double(position), color: color, customID: nil))
                }
            }
        }
        for guide in GuideStore.shared.guides {
            result.append(ResolvedGuide(axis: guide.axis, position: guide.position, color: .systemPink, customID: guide.id))
        }
        return result
    }

    /// Each display's panel in physical inches, for drawing guides on the real screens.
    func displayPanelRects() -> [CGDirectDisplayID: CGRect] {
        Dictionary(uniqueKeysWithValues: physicalLayout.displays.map { ($0.id, CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)) })
    }

    /// The physical position a guide of `axis` takes when dragged to `point`.
    private func guidePosition(for point: CGPoint, axis: GuideAxis) -> Double {
        let physical = viewToPhysical(point)
        return Double(axis == .horizontal ? physical.y : physical.x)
    }

    private func isOverRuler(_ point: CGPoint) -> Bool {
        point.x <= rulerSize || point.y >= bounds.maxY - rulerSize
    }

    /// Which kind of guide a mouse-down at `point` would pull out of a ruler.
    private func rulerAxis(at point: CGPoint) -> GuideAxis? {
        if point.y >= bounds.maxY - rulerSize && point.x > rulerSize { return .horizontal }
        if point.x <= rulerSize && point.y < bounds.maxY - rulerSize { return .vertical }
        return nil
    }

    /// The custom guide within a few points of `point`.
    private func customGuide(at point: CGPoint) -> Guide? {
        guard GuideSettings.showGuides, !isOverRuler(point) else { return nil }
        return GuideStore.shared.guides.reversed().first { guide in
            switch guide.axis {
            case .horizontal: return abs(point.y - (CGFloat(guide.position) * pointsPerInch + viewOffset.y)) <= 4
            case .vertical: return abs(point.x - (CGFloat(guide.position) * pointsPerInch + viewOffset.x)) <= 4
            }
        }
    }

    private func drawGuides() {
        let guides = resolvedGuides()
        guard !guides.isEmpty else { return }
        for guide in guides {
            let isActive = guide.customID != nil && (guide.customID == hoverGuideID || guide.customID == guideDrag)
            let path = NSBezierPath()
            switch guide.axis {
            case .horizontal:
                let y = CGFloat(guide.position) * pointsPerInch + viewOffset.y
                path.move(to: CGPoint(x: rulerSize, y: y)); path.line(to: CGPoint(x: bounds.maxX, y: y))
            case .vertical:
                let x = CGFloat(guide.position) * pointsPerInch + viewOffset.x
                path.move(to: CGPoint(x: x, y: 0)); path.line(to: CGPoint(x: x, y: bounds.maxY - rulerSize))
            }
            // A dark line underneath keeps the guide visible over bright displays and images.
            NSColor.black.withAlphaComponent(0.35).setStroke()
            path.lineWidth = isActive ? 4 : 3
            path.stroke()
            guide.color.setStroke()
            path.lineWidth = isActive ? 2.5 : 1.25
            if !guide.isCustom { path.setLineDash([6, 4], count: 2, phase: 0) }
            path.stroke()
        }
    }

    /// While a guide is dragged, its position is shown next to the cursor.
    private func drawGuideDragLabel() {
        guard let guideDrag, let guide = GuideStore.shared.guide(withID: guideDrag) else { return }
        let text = "\(MeasurementFormat.string(guide.position)) in" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attributes)
        let origin = CGPoint(x: min(guideDragPoint.x + 14, bounds.maxX - size.width - 14), y: min(max(guideDragPoint.y - size.height - 10, 4), bounds.maxY - size.height - 4))
        let pill = CGRect(x: origin.x - 6, y: origin.y - 2, width: size.width + 12, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
        text.draw(at: origin, withAttributes: attributes)
    }

    // MARK: - Rulers
    private let rulerSize: CGFloat = 20

    /// Spacing between labeled ruler ticks, in inches, chosen for the current zoom.
    private func rulerMajorSpacing() -> Double {
        let candidates: [Double] = [0.0625, 0.125, 0.25, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000]
        return candidates.first { $0 * Double(pointsPerInch) >= 70 } ?? 1000
    }

    private func rulerLabel(_ value: Double) -> String {
        MeasurementFormat.useFractions ? MeasurementFormat.fractionString(value) : String(format: "%g", (value * 10000).rounded() / 10000)
    }

    private func drawRulers() {
        let topStrip = CGRect(x: 0, y: bounds.maxY - rulerSize, width: bounds.width, height: rulerSize)
        let leftStrip = CGRect(x: 0, y: 0, width: rulerSize, height: bounds.height - rulerSize)
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        topStrip.fill()
        leftStrip.fill()
        NSColor.separatorColor.setStroke()
        let edges = NSBezierPath()
        edges.move(to: CGPoint(x: 0, y: topStrip.minY)); edges.line(to: CGPoint(x: bounds.maxX, y: topStrip.minY))
        edges.move(to: CGPoint(x: leftStrip.maxX, y: 0)); edges.line(to: CGPoint(x: leftStrip.maxX, y: topStrip.minY))
        edges.lineWidth = 1
        edges.stroke()

        let major = rulerMajorSpacing()
        let divisions: Double = major < 1 ? 4 : 5
        let minor = major / divisions
        let scale = Double(pointsPerInch)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor.secondaryLabelColor]
        let tickPath = NSBezierPath()
        tickPath.lineWidth = 1

        // Top ruler: x positions.
        let firstX = Int(floor((Double(rulerSize - viewOffset.x)) / scale / minor))
        let lastX = Int(ceil((Double(bounds.maxX - viewOffset.x)) / scale / minor))
        for index in firstX...max(firstX, lastX) {
            let value = Double(index) * minor
            let x = CGFloat(value * scale) + viewOffset.x
            guard x > rulerSize else { continue }
            let isMajor = index % Int(divisions) == 0
            tickPath.move(to: CGPoint(x: x, y: topStrip.minY)); tickPath.line(to: CGPoint(x: x, y: topStrip.minY + (isMajor ? 9 : 4)))
            if isMajor { (rulerLabel(value) as NSString).draw(at: CGPoint(x: x + 3, y: topStrip.minY + 7), withAttributes: attributes) }
        }
        // Left ruler: y positions, with the labels turned to read upward.
        let firstY = Int(floor(Double(0 - viewOffset.y) / scale / minor))
        let lastY = Int(ceil(Double(topStrip.minY - viewOffset.y) / scale / minor))
        for index in firstY...max(firstY, lastY) {
            let value = Double(index) * minor
            let y = CGFloat(value * scale) + viewOffset.y
            guard y < topStrip.minY else { continue }
            let isMajor = index % Int(divisions) == 0
            tickPath.move(to: CGPoint(x: leftStrip.maxX, y: y)); tickPath.line(to: CGPoint(x: leftStrip.maxX - (isMajor ? 9 : 4), y: y))
            if isMajor {
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: leftStrip.maxX - 9, yBy: y + 3)
                transform.rotate(byDegrees: 90)
                transform.concat()
                (rulerLabel(value) as NSString).draw(at: .zero, withAttributes: attributes)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        NSColor.tertiaryLabelColor.setStroke()
        tickPath.stroke()

        // Marks where each guide crosses the rulers.
        for guide in resolvedGuides() where guide.isCustom {
            let mark = NSBezierPath()
            mark.lineWidth = 2
            switch guide.axis {
            case .vertical:
                let x = CGFloat(guide.position) * pointsPerInch + viewOffset.x
                mark.move(to: CGPoint(x: x, y: topStrip.minY)); mark.line(to: CGPoint(x: x, y: bounds.maxY))
            case .horizontal:
                let y = CGFloat(guide.position) * pointsPerInch + viewOffset.y
                mark.move(to: CGPoint(x: 0, y: y)); mark.line(to: CGPoint(x: leftStrip.maxX, y: y))
            }
            guide.color.setStroke()
            mark.stroke()
        }
    }

    // MARK: - Zoom to Fit
    /// What Zoom to Fit and Center View frame, in physical inches: the selected
    /// display, or all displays as a group (bezels included) when none is selected.
    private func focusRect() -> CGRect? {
        let targets: [PhysicalLayout.Display]
        if let id = selectedDisplayID, let selected = physicalLayout.displays.first(where: { $0.id == id }) {
            targets = [selected]
        } else {
            targets = physicalLayout.displays
        }
        let rects = targets.map(outerPhysicalRect)
        guard var union = rects.first else { return nil }
        for rect in rects.dropFirst() { union = union.union(rect) }
        return union
    }

    // Space kept clear for the buttons along the bottom edge and a margin along the top.
    private let focusMarginSides: CGFloat = 40
    private let focusMarginTop: CGFloat = 40
    private let focusMarginBottom: CGFloat = 60

    @objc func zoomToFit(
        initialZoomFactor: CGFloat = 1.0
    ) {
        guard let focus = focusRect(),
              focus.width > 0,
              focus.height > 0 else {
            return
        }

        let availableWidth = bounds.width - focusMarginSides * 2
        let availableHeight = bounds.height - focusMarginTop - focusMarginBottom
        guard availableWidth > 0, availableHeight > 0 else {
            return
        }

        let fitZoom = min(
            availableWidth / (focus.width * basePointsPerInch),
            availableHeight / (focus.height * basePointsPerInch)
        )
        zoom = min(max(fitZoom * initialZoomFactor, 0.05), 10.0)

        centerView()
    }

    @objc func zoomToFitFromButton() {
        zoomToFit(initialZoomFactor: 1.0)
    }

    // MARK: - Center View
    @objc func centerView() {
        let center = focusRect().map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero
        let viewCenter = CGPoint(
            x: bounds.midX,
            y: focusMarginBottom + (bounds.height - focusMarginBottom - focusMarginTop) / 2
        )
        // viewOffset is where physical (0, 0) lands in the view.
        viewOffset = CGPoint(
            x: viewCenter.x - center.x * pointsPerInch,
            y: viewCenter.y - center.y * pointsPerInch
        )
        needsDisplay = true
    }

    // MARK: - Wallpaper Export
    /// Cuts the wallpaper into one native-resolution image per display, or nil if there is no wallpaper.
    func wallpaperExport() -> WallpaperExport? {
        guard let source = wallpaperLayer.image,
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let imageRect = physicalRect(of: wallpaperLayer),
              imageRect.width > 0 else { return nil }
        var slices: [WallpaperSlice] = []
        var neededPPI = 0.0
        for info in displays {
            guard let placed = physicalLayout.displays.first(where: { $0.id == info.displayID }),
                  let rendered = WallpaperSlicer.render(
                    image: cgImage, imageRect: imageRect,
                    panelRect: CGRect(x: placed.x, y: placed.y, width: placed.width, height: placed.height),
                    pixelWidth: info.pixelWidth, pixelHeight: info.pixelHeight
                  ) else { continue }
            slices.append(WallpaperSlice(displayID: info.displayID, persistentID: info.persistentID, name: info.nickname, pixelWidth: info.pixelWidth, pixelHeight: info.pixelHeight, image: rendered))
            neededPPI = max(neededPPI, Double(info.pixelWidth) / max(Double(placed.width), 0.01))
        }
        return WallpaperExport(slices: slices, imagePixelsPerInch: Double(cgImage.width) / Double(imageRect.width), neededPixelsPerInch: neededPPI)
    }

    // MARK: - Refresh
    /// Re-reads the connected displays from macOS, keeping the selection if it still exists.
    func reloadDisplays() {
        let previous = selectedDisplayID
        displays = DisplayInfo.detectDisplays()
        if let previous, !displays.contains(where: { $0.displayID == previous }) {
            select(nil)
        } else if previous != nil {
            onSelectionChanged?(selectedDisplayInfo())
        }
        needsDisplay = true
    }

    // MARK: - Mouse
    /// Selects a display or the reference image, or clears the selection.
    private func select(_ target: EditTarget?) {
        selectedDisplayID = nil
        selectedImage = nil
        switch target {
        case .display(let id): selectedDisplayID = id
        case .image(let slot): selectedImage = slot
        case nil: break
        }
        onSelectionChanged?(selectedDisplayInfo())
        needsDisplay = true
    }

    override func mouseDown(
        with event: NSEvent
    ) {
        let point = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)

        // Dragging out of a ruler creates a guide; dragging a custom guide moves it.
        if let axis = rulerAxis(at: point) {
            GuideSettings.showGuides = true
            let guide = Guide(axis: axis, position: guidePosition(for: point, axis: axis))
            GuideStore.shared.add(guide)
            guideDrag = guide.id
            guideDragPoint = point
            return
        }
        if let guide = customGuide(at: point) {
            guideDrag = guide.id
            guideDragPoint = point
            return
        }

        // The lock icon is only visible (and clickable) on locked or selected displays.
        if let locked = physicalLayout.displays.reversed().first(where: {
            ($0.isLocked || $0.id == selectedDisplayID) && lockIconRect(in: physicalRectToView($0)).contains(point)
        }) {
            select(.display(locked.id))
            updateSelectedDisplay(DisplayEdit(isLocked: !locked.isLocked))
            return
        }

        // Image lock icons behave the same way.
        if let slot = imageSlots.reversed().first(where: { imageLockIconRect($0)?.contains(point) == true }) {
            select(.image(slot))
            let locked = !layer(slot).isLocked
            setImageLocked(locked, for: slot)
            onImageLockChanged?(slot, locked)
            return
        }

        // Clicking an item selects it and starts moving it, or resizing it from a handle.
        // Clicking empty workspace clears the selection and begins panning.
        if let hit = itemHit(point) {
            select(hit.target)
            isPanning = false
            guard isEditable(hit.target), let start = physicalOuterRect(of: hit.target) else { return }
            dragTarget = hit.target
            dragMode = hit.handle.map(DragMode.resize) ?? .move
            dragStartPoint = point
            dragStartRect = start
            return
        }

        // Shift-drag on the background zooms, keeping the selection.
        if event.modifierFlags.contains(.shift) {
            isZoomDragging = true
            zoomDragStart = point
            zoomDragStartZoom = zoom
            zoomDragAnchor = viewToPhysical(point)
            return
        }

        select(nil)
        panStartPoint = point
        panStartOffset = viewOffset
        isPanning = true
    }

    override func mouseDragged(
        with event: NSEvent
    ) {
        let currentPoint = convert(event.locationInWindow, from: nil)

        if let guideDrag, let guide = GuideStore.shared.guide(withID: guideDrag) {
            GuideStore.shared.setPosition(guidePosition(for: currentPoint, axis: guide.axis), for: guideDrag)
            guideDragPoint = currentPoint
            return
        }

        if let dragTarget {
            let rect: CGRect
            switch dragMode {
            case .move:
                rect = dragStartRect.offsetBy(
                    dx: (currentPoint.x - dragStartPoint.x) / pointsPerInch,
                    dy: (currentPoint.y - dragStartPoint.y) / pointsPerInch
                )
            case .resize(let handle):
                var minSize = CGSize(width: minimumItemSize, height: minimumItemSize)
                if case .display(let id) = dragTarget, let d = physicalLayout.displays.first(where: { $0.id == id }) {
                    let i = bezelInsets(d)
                    minSize = CGSize(width: i.left + i.right + minimumItemSize, height: i.top + i.bottom + minimumItemSize)
                }
                rect = resizedRect(dragStartRect, handle: handle, to: viewToPhysical(currentPoint), keepAspect: { if case .image = dragTarget { return true } else { return false } }(), minSize: minSize)
            }
            apply(rect, to: dragTarget)
            return
        }

        if isZoomDragging {
            // Dragging up zooms in, down zooms out; the point under the cursor at the start stays put.
            let newZoom = min(max(zoomDragStartZoom * exp((currentPoint.y - zoomDragStart.y) * 0.01), 0.05), 10)
            zoom = newZoom
            viewOffset = CGPoint(
                x: zoomDragStart.x - zoomDragAnchor.x * pointsPerInch,
                y: zoomDragStart.y - zoomDragAnchor.y * pointsPerInch
            )
            needsDisplay = true
            return
        }

        guard isPanning else {
            return
        }

        let dx = currentPoint.x - panStartPoint.x
        let dy = currentPoint.y - panStartPoint.y
        viewOffset = CGPoint(
            x: panStartOffset.x + dx,
            y: panStartOffset.y + dy
        )
        needsDisplay = true
    }

    /// Moves or resizes an item so its footprint (including bezel for displays) is `rect`.
    private func apply(_ rect: CGRect, to target: EditTarget) {
        switch target {
        case .image(let slot):
            let frame = ImageFrame(centerX: Double(rect.midX), centerY: Double(rect.midY), width: Double(rect.width))
            setFrame(frame, for: slot)
            onImageFrameChanged?(slot, frame)
        case .display(let id):
            guard let j = physicalLayout.displays.firstIndex(where: { $0.id == id }),
                  let i = displays.firstIndex(where: { $0.displayID == id }) else { return }
            let insets = bezelInsets(physicalLayout.displays[j])
            let panel = CGRect(x: rect.minX + insets.left, y: rect.minY + insets.bottom, width: rect.width - insets.left - insets.right, height: rect.height - insets.top - insets.bottom)
            physicalLayout.displays[j].x = panel.minX
            physicalLayout.displays[j].y = panel.minY
            physicalLayout.displays[j].width = panel.width
            physicalLayout.displays[j].height = panel.height
            suppressDisplayRebuild = true
            displays[i].physicalWidthInches = Double(panel.width)
            displays[i].physicalHeightInches = Double(panel.height)
            suppressDisplayRebuild = false
            syncSelectedLayoutToDisplay(save: false)
            needsDisplay = true
            onDisplayValuesChanged?(displays[i], physicalLayout.displays[j].centerX, physicalLayout.displays[j].centerY)
        }
    }

    override func mouseUp(
        with event: NSEvent
    ) {
        if let guideDrag, let guide = GuideStore.shared.guide(withID: guideDrag) {
            // Dropping a guide back on its ruler removes it.
            let point = convert(event.locationInWindow, from: nil)
            let onRuler = guide.axis == .horizontal ? point.x <= rulerSize : point.y >= bounds.maxY - rulerSize
            if onRuler { GuideStore.shared.remove(guideDrag) } else { GuideStore.shared.save() }
            self.guideDrag = nil
            needsDisplay = true
            return
        }
        isPanning = false
        isZoomDragging = false
        if case .display? = dragTarget {
            syncSelectedLayoutToDisplay(save: true)
        }
        dragTarget = nil
    }

    func selectedDisplayInfo() -> DisplayInfo? {
        guard let id = selectedDisplayID else { return nil }
        return displays.first(where: { $0.displayID == id })
    }

    func selectedPosition() -> (x: CGFloat, y: CGFloat)? {
        guard let id = selectedDisplayID, let item = physicalLayout.displays.first(where: { $0.id == id }) else { return nil }
        return (item.centerX, item.centerY)
    }

    func updateSelectedDisplay(_ edit: DisplayEdit) {
        guard let id = selectedDisplayID, let i = displays.firstIndex(where: { $0.displayID == id }), let j = physicalLayout.displays.firstIndex(where: { $0.id == id }) else { return }
        // A locked display only accepts the change that unlocks it.
        if displays[i].isLocked && edit.isLocked == nil { return }
        suppressDisplayRebuild = true
        if let nickname = edit.nickname, !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { displays[i].nickname = nickname; physicalLayout.displays[j].nickname = nickname }
        // Position is the display's center, so resizing grows it evenly around that point.
        let center = CGPoint(x: physicalLayout.displays[j].centerX, y: physicalLayout.displays[j].centerY)
        if let width = edit.width, width > 0.1 { displays[i].physicalWidthInches = width; physicalLayout.displays[j].width = CGFloat(width) }
        if let height = edit.height, height > 0.1 { displays[i].physicalHeightInches = height; physicalLayout.displays[j].height = CGFloat(height) }
        physicalLayout.displays[j].x = (edit.x.map { CGFloat($0) } ?? center.x) - physicalLayout.displays[j].width / 2
        physicalLayout.displays[j].y = (edit.y.map { CGFloat($0) } ?? center.y) - physicalLayout.displays[j].height / 2
        if let color = edit.color { displays[i].isColorCustom = true; displays[i].colorHex = color.displayHex; physicalLayout.displays[j].colorHex = color.displayHex }
        if let bezelColor = edit.bezelColor { displays[i].bezelColorHex = bezelColor.displayHex; physicalLayout.displays[j].bezelColorHex = bezelColor.displayHex }
        if let uniformBezel = edit.uniformBezel { displays[i].uniformBezel = uniformBezel; physicalLayout.displays[j].uniformBezel = uniformBezel }
        if let bezelUniform = edit.bezelUniform { displays[i].bezelUniform = bezelUniform; physicalLayout.displays[j].bezelUniform = CGFloat(bezelUniform) }
        if let bezelTop = edit.bezelTop { displays[i].bezelTop = bezelTop; physicalLayout.displays[j].bezelTop = CGFloat(bezelTop) }
        if let bezelBottom = edit.bezelBottom { displays[i].bezelBottom = bezelBottom; physicalLayout.displays[j].bezelBottom = CGFloat(bezelBottom) }
        if let bezelLeft = edit.bezelLeft { displays[i].bezelLeft = bezelLeft; physicalLayout.displays[j].bezelLeft = CGFloat(bezelLeft) }
        if let bezelRight = edit.bezelRight { displays[i].bezelRight = bezelRight; physicalLayout.displays[j].bezelRight = CGFloat(bezelRight) }
        if let showBezel = edit.showBezel { displays[i].showBezel = showBezel; physicalLayout.displays[j].showBezel = showBezel }
        if let isLocked = edit.isLocked { displays[i].isLocked = isLocked; physicalLayout.displays[j].isLocked = isLocked }
        suppressDisplayRebuild = false
        syncSelectedLayoutToDisplay(save: true)
        needsDisplay = true
        onDisplayValuesChanged?(displays[i], physicalLayout.displays[j].centerX, physicalLayout.displays[j].centerY)
    }

    private func syncSelectedLayoutToDisplay(save: Bool) {
        guard let id = selectedDisplayID, let item = physicalLayout.displays.first(where: { $0.id == id }), let i = displays.firstIndex(where: { $0.displayID == id }) else { return }
        var configuration = displays[i].makeConfiguration()
        configuration.xInches = Double(item.x); configuration.yInches = Double(item.y)
        configuration.widthInches = displays[i].physicalWidthInches; configuration.heightInches = displays[i].physicalHeightInches
        configuration.nickname = displays[i].nickname; configuration.colorHex = displays[i].colorHex
        configuration.uniformBezel = displays[i].uniformBezel
        configuration.bezelTop = displays[i].bezelTop; configuration.bezelBottom = displays[i].bezelBottom
        configuration.bezelLeft = displays[i].bezelLeft; configuration.bezelRight = displays[i].bezelRight
        configuration.bezelColorHex = displays[i].bezelColorHex; configuration.showBezel = displays[i].showBezel; configuration.isLocked = displays[i].isLocked
        if save { DisplayConfigurationStore.shared.save(configuration) }
    }

    // MARK: - Scroll Zoom
    /// Sets the zoom, keeping the physical point under `anchor` (in view coordinates) where it is.
    private func setZoom(_ newZoom: CGFloat, keeping anchor: CGPoint) {
        let physical = viewToPhysical(anchor)
        zoom = min(max(newZoom, 0.05), 10.0)
        viewOffset = CGPoint(
            x: anchor.x - physical.x * pointsPerInch,
            y: anchor.y - physical.y * pointsPerInch
        )
        needsDisplay = true
    }

    override func scrollWheel(
        with event: NSEvent
    ) {
        // Zoom around the cursor, or around the middle of the viewport if the cursor is outside it.
        let location = convert(event.locationInWindow, from: nil)
        let anchor = bounds.contains(location) ? location : CGPoint(x: bounds.midX, y: bounds.midY)
        setZoom(zoom * exp(CGFloat(event.scrollingDeltaY) * 0.01), keeping: anchor)
    }

    /// Trackpad pinch: zoom around the point between the fingers.
    override func magnify(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let anchor = bounds.contains(location) ? location : CGPoint(x: bounds.midX, y: bounds.midY)
        setZoom(zoom * (1 + event.magnification), keeping: anchor)
    }
}
