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
    /// Every selected display. A single selected display shows its properties; several don't.
    private(set) var selectedDisplayIDs: Set<CGDirectDisplayID> = []
    /// The selected display when exactly one is selected.
    var selectedDisplayID: CGDirectDisplayID? { selectedDisplayIDs.count == 1 ? selectedDisplayIDs.first : nil }
    /// Selected custom guides, which move together with selected displays.
    private var selectedGuideIDs: Set<UUID> = []

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
    // The group being dragged: where each selected display and guide started.
    private var groupDisplayStart: [CGDirectDisplayID: CGRect] = [:]
    private var groupGuideStart: [UUID: Double] = [:]
    /// A click inside a multiple selection keeps the group for dragging; if it turns out
    /// to be a plain click, it narrows the selection to that display.
    private var pendingCollapse: EditTarget?
    private var didDrag = false
    /// A gap measurement being dragged, and which display's side of it was grabbed.
    private struct GapDrag {
        let measurement: GapMeasurement
        let zone: GapZone
        let startPoint: CGPoint
        let startRect: CGRect?
    }
    private var gapDrag: GapDrag?
    private var hoverGapKey: String?
    private var hoverGapZone: GapZone?

    /// Parts of a gap measurement: the two ends grab the displays beside them,
    /// and the middle only slides the arrow along the gap.
    private enum GapZone {
        case first, middle, second
    }
    /// Shift-dragging the background zooms around the point where the drag began.
    private var isZoomDragging = false
    private var zoomDragStart = CGPoint.zero
    private var zoomDragStartZoom: CGFloat = 1
    private var zoomDragAnchor = CGPoint.zero
    private var zoomDragAnchorPoint = CGPoint.zero
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
        /// Turning an image: the pointer's angle and the image's rotation when the drag began.
        case rotate(startAngle: CGFloat, startRotation: CGFloat)
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
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
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
                isSelected: selectedDisplayIDs.contains(display.id),
                label: DisplayIdentity.label(forIndex: index)
            )
        }
        for slot in imageSlots where drawsAboveDisplays(slot) { drawImageLayer(slot) }
        drawImageLockIcons(in: context)
        drawGuides()
        drawGapMeasurements()
        drawGroupSelection()
        var withHandles: [EditTarget] = []
        for target in [currentSelection, hoverTarget].compactMap({ $0 }) where !withHandles.contains(target) {
            withHandles.append(target)
            drawHandles(for: target, in: context)
        }
        drawAnchorIfNeeded()
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
        let turn = CGFloat(current.frame?.rotation ?? 0)
        func drawImage(opacity: CGFloat) {
            NSGraphicsContext.saveGraphicsState()
            if turn != 0, let context = NSGraphicsContext.current?.cgContext {
                // Turn the image about its own center.
                context.translateBy(x: target.midX, y: target.midY)
                context.rotate(by: turn * .pi / 180)
                context.translateBy(x: -target.midX, y: -target.midY)
            }
            image.draw(in: target, from: .zero, operation: .sourceOver, fraction: opacity, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
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

        // The caption is centered between the bottom of the circle and the bottom of the display.
        let box = CGRect(x: rect.minX + 8, y: rect.minY + 6, width: max(rect.width - 16, 1), height: max(circle.minY - rect.minY - 12, 1))
        func height(of line: (text: String, attributes: [NSAttributedString.Key: Any])) -> CGFloat {
            ceil((line.text as NSString).boundingRect(with: CGSize(width: box.width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: line.attributes).height)
        }
        while lines.count > 1, lines.reduce(0, { $0 + height(of: $1) }) > box.height { lines.removeLast() }
        guard let first = lines.first, height(of: first) <= box.height else { return }

        var top = box.midY + lines.reduce(0, { $0 + height(of: $1) }) / 2
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
        // The icon sits in the image's top-right corner and turns with it.
        let corner = CGPoint(x: rect.maxX - lockIconSize / 2 - 8, y: rect.maxY - lockIconSize / 2 - 8)
        let c = rotatedPoint(corner, about: CGPoint(x: rect.midX, y: rect.midY), degrees: CGFloat(current.frame?.rotation ?? 0))
        return CGRect(x: c.x - lockIconSize / 2, y: c.y - lockIconSize / 2, width: lockIconSize, height: lockIconSize)
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
    private func handleCenter(_ handle: GrabHandle, in rect: CGRect, rotation: CGFloat = 0) -> CGPoint {
        let point = CGPoint(x: rect.minX + handle.unit.x * rect.width, y: rect.minY + handle.unit.y * rect.height)
        return rotatedPoint(point, about: CGPoint(x: rect.midX, y: rect.midY), degrees: rotation)
    }

    private func handle(at point: CGPoint, in rect: CGRect, rotation: CGFloat = 0) -> GrabHandle? {
        // Corners first so they win where an edge dot is close by.
        let ordered = GrabHandle.allCases.sorted { $0.isCorner && !$1.isCorner }
        return ordered.first { handle in
            let c = handleCenter(handle, in: rect, rotation: rotation)
            let r = (handle.isCorner ? cornerHandleRadius : edgeHandleRadius) + 3
            return hypot(point.x - c.x, point.y - c.y) <= r
        }
    }

    // MARK: - Rotation Handle
    private let rotationHandleDistance: CGFloat = 30

    /// The knob above an image's top edge that turns it, with where its stem starts, in view coordinates.
    private func rotationHandle(for target: EditTarget) -> (base: CGPoint, knob: CGPoint)? {
        guard case .image = target, isEditable(target), let physical = physicalOuterRect(of: target) else { return nil }
        let rect = viewRect(forPhysical: physical)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let angle = rotation(of: target)
        return (
            rotatedPoint(CGPoint(x: rect.midX, y: rect.maxY), about: center, degrees: angle),
            rotatedPoint(CGPoint(x: rect.midX, y: rect.maxY + rotationHandleDistance), about: center, degrees: angle)
        )
    }

    /// The image whose rotation knob is under `point`.
    private func rotateHit(at point: CGPoint) -> EditTarget? {
        for target in [currentSelection, hoverTarget].compactMap({ $0 }) {
            if let knob = rotationHandle(for: target)?.knob, hypot(point.x - knob.x, point.y - knob.y) <= 9 { return target }
        }
        return nil
    }

    private func handleColor(for target: EditTarget) -> NSColor {
        if case .display(let id) = target, let d = physicalLayout.displays.first(where: { $0.id == id }) { return NSColor(displayHex: d.colorHex) }
        return .controlAccentColor
    }

    /// An outline in the item's color with dots at the corners and edge midpoints,
    /// plus a rotation knob for images.
    private func drawHandles(for target: EditTarget, in context: CGContext) {
        guard isEditable(target), let physical = physicalOuterRect(of: target) else { return }
        let rect = viewRect(forPhysical: physical)
        let angle = rotation(of: target)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let color = handleColor(for: target)
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2)
        // The outline follows the item's turn.
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            .map { rotatedPoint($0, about: center, degrees: angle) }
        context.addLines(between: corners + [corners[0]])
        context.strokePath()

        if let knob = rotationHandle(for: target) {
            context.setStrokeColor(color.cgColor)
            context.move(to: knob.base); context.addLine(to: knob.knob)
            context.strokePath()
            let dot = CGRect(x: knob.knob.x - 6, y: knob.knob.y - 6, width: 12, height: 12)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: dot)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: dot)
        }
        for handle in GrabHandle.allCases {
            let c = handleCenter(handle, in: rect, rotation: angle)
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

    /// The new rectangle when `handle` is dragged to `p`.
    /// - `keepAspect`: scale proportionally; otherwise each dimension follows the pointer on its own.
    /// - `fromCenter`: grow or shrink equally around the center; otherwise the opposite corner or edge stays put.
    private func resizedRect(_ r: CGRect, handle: GrabHandle, to p: CGPoint, keepAspect: Bool, fromCenter: Bool, minSize: CGSize) -> CGRect {
        let u = handle.unit
        let changesX = u.x != 0.5, changesY = u.y != 0.5
        let center = CGPoint(x: r.midX, y: r.midY)
        // The fixed point opposite the handle, when anchoring there.
        let anchor = CGPoint(x: r.minX + (1 - u.x) * r.width, y: r.minY + (1 - u.y) * r.height)

        var w = r.width, h = r.height
        if fromCenter {
            if changesX { w = max(minSize.width, 2 * abs(p.x - center.x)) }
            if changesY { h = max(minSize.height, 2 * abs(p.y - center.y)) }
        } else {
            if changesX { w = max(minSize.width, u.x == 0 ? anchor.x - p.x : p.x - anchor.x) }
            if changesY { h = max(minSize.height, u.y == 0 ? anchor.y - p.y : p.y - anchor.y) }
        }
        if keepAspect {
            let aspect = r.width / max(r.height, 0.0001)
            if changesX && changesY {
                let scale = max(w / r.width, h / r.height)
                w = r.width * scale; h = r.height * scale
            } else if changesX {
                h = w / aspect
            } else {
                w = h * aspect
            }
        }
        if fromCenter { return CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h) }
        let x = u.x == 0 ? anchor.x - w : (u.x == 1 ? anchor.x : r.midX - w / 2)
        let y = u.y == 0 ? anchor.y - h : (u.y == 1 ? anchor.y : r.midY - h / 2)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Hit Testing
    /// Whether `point` is inside an item's body, allowing for the item's turn and some `slop`.
    private func body(of target: EditTarget, contains point: CGPoint, slop: CGFloat = 0) -> Bool {
        guard let physical = physicalOuterRect(of: target) else { return false }
        let rect = viewRect(forPhysical: physical)
        let local = rotatedPoint(point, about: CGPoint(x: rect.midX, y: rect.midY), degrees: -rotation(of: target))
        return rect.insetBy(dx: -slop, dy: -slop).contains(local)
    }

    /// What is under `point`: a handle of the selected or hovered item, or an item's body.
    private func itemHit(_ point: CGPoint) -> (target: EditTarget, handle: GrabHandle?)? {
        for target in [currentSelection, hoverTarget].compactMap({ $0 }) where isEditable(target) {
            if let physical = physicalOuterRect(of: target),
               let handle = handle(at: point, in: viewRect(forPhysical: physical), rotation: rotation(of: target)) {
                return (target, handle)
            }
        }
        for target in targetsFrontToBack() where body(of: target, contains: point) { return (target, nil) }
        return nil
    }

    /// Like `itemHit`, but forgiving enough to keep handles that hang outside an item's edge visible.
    private func hoverTest(_ point: CGPoint) -> EditTarget? {
        if let target = rotateHit(at: point) { return target }
        if let hit = itemHit(point) { return hit.target }
        let slop = cornerHandleRadius + 3
        return targetsFrontToBack().first { isEditable($0) && body(of: $0, contains: point, slop: slop) }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let target = hoverTest(point)
        if target != hoverTarget { hoverTarget = target; needsDisplay = true }
        let handleUnderMouse = itemHit(point)?.handle
        if handleUnderMouse != hoverHandle { hoverHandle = handleUnderMouse; needsDisplay = true }

        // Custom guides highlight under the mouse.
        let guide = rulerAxis(at: point) == nil ? customGuide(at: point) : nil
        if guide?.id != hoverGuideID {
            hoverGuideID = guide?.id
            needsDisplay = true
        }
        let gap = guide == nil && rulerAxis(at: point) == nil ? gapMeasurement(at: point) : nil
        if gap?.measurement.key != hoverGapKey || gap?.zone != hoverGapZone {
            hoverGapKey = gap?.measurement.key
            hoverGapZone = gap?.zone
            needsDisplay = true
        }
        cursor(at: point).set()
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor(at: convert(event.locationInWindow, from: nil)).set()
    }

    // MARK: - Cursors
    private func resizeCursor(_ handle: GrabHandle, rotation: CGFloat = 0) -> NSCursor {
        let base: CGFloat
        switch handle {
        case .left, .right: base = 0
        case .top, .bottom: base = 90
        case .topRight, .bottomLeft: base = 45
        case .topLeft, .bottomRight: base = 135
        }
        return ToolCursors.resize(angle: base + rotation)
    }

    /// A horizontal guide moves up and down; a vertical one left and right.
    private func guideCursor(_ axis: GuideAxis) -> NSCursor {
        ToolCursors.resize(angle: axis == .horizontal ? 90 : 0)
    }

    /// The ends of a gap arrow move displays across the gap; the middle slides along it.
    private func gapCursor(_ measurement: GapMeasurement, zone: GapZone) -> NSCursor {
        let acrossIsHorizontal = measurement.direction == .horizontal
        return ToolCursors.resize(angle: acrossIsHorizontal == (zone != .middle) ? 0 : 90)
    }

    /// The cursor for whatever is under `point`: an arrow pointing the way a drag from there would go.
    private func cursor(at point: CGPoint) -> NSCursor {
        if let axis = rulerAxis(at: point) { return guideCursor(axis) }
        if let guide = customGuide(at: point) { return guideCursor(guide.axis) }
        if let gap = gapMeasurement(at: point) { return gapCursor(gap.measurement, zone: gap.zone) }
        if rotateHit(at: point) != nil { return ToolCursors.rotate }
        if let hit = itemHit(point), let handle = hit.handle { return resizeCursor(handle, rotation: rotation(of: hit.target)) }
        return .arrow
    }

    /// How far an item is turned, in degrees counterclockwise. Displays aren't.
    private func rotation(of target: EditTarget) -> CGFloat {
        if case .image(let slot) = target { return CGFloat(layer(slot).frame?.rotation ?? 0) }
        return 0
    }

    /// `p` turned counterclockwise by `degrees` about `center`.
    private func rotatedPoint(_ p: CGPoint, about center: CGPoint, degrees: CGFloat) -> CGPoint {
        guard degrees != 0 else { return p }
        let radians = degrees * .pi / 180
        let dx = p.x - center.x, dy = p.y - center.y
        return CGPoint(x: center.x + dx * cos(radians) - dy * sin(radians), y: center.y + dx * sin(radians) + dy * cos(radians))
    }

    override func mouseExited(with event: NSEvent) {
        if hoverTarget != nil { hoverTarget = nil; needsDisplay = true }
        if hoverHandle != nil { hoverHandle = nil; needsDisplay = true }
        if hoverGuideID != nil { hoverGuideID = nil; needsDisplay = true }
        if hoverGapKey != nil { hoverGapKey = nil; hoverGapZone = nil; needsDisplay = true }
        NSCursor.arrow.set()
    }

    // MARK: - Guide Editing
    override var acceptsFirstResponder: Bool { true }

    /// Delete or Backspace removes the custom guide under the mouse.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117, !selectedGuideIDs.isEmpty || hoverGuideID != nil {
            // Delete removes the selected guides, or the one under the mouse if none are selected.
            let doomed = selectedGuideIDs.isEmpty ? [hoverGuideID].compactMap { $0 } : Array(selectedGuideIDs)
            UndoCenter.shared.perform(doomed.count > 1 ? "Delete Guides" : "Delete Guide") { for id in doomed { GuideStore.shared.remove(id) } }
            selectedGuideIDs = []
            hoverGuideID = nil
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
        // Control is a modifier for dragging (it flips snapping), so a Control-click isn't a right click.
        // Right click and a two-finger click still open the menu.
        if event.type == .leftMouseDown { return nil }
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
        if let id = (sender.representedObject as? GuideMenuPayload)?.id { UndoCenter.shared.perform("Delete Guide") { GuideStore.shared.remove(id) } }
    }

    @objc private func addGuideFromMenu(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? GuideMenuPayload, let axis = payload.axis else { return }
        GuideSettings.showCustomGuides = true
        UndoCenter.shared.perform("Add Guide") {
            GuideStore.shared.add(Guide(axis: axis, position: payload.position))
            GuideStore.shared.save()
        }
    }

    @objc private func clearGuidesFromMenu() { UndoCenter.shared.perform("Clear Guides") { GuideStore.shared.removeAll() } }

    // MARK: - Guides
    /// Every guide to draw: edge guides from the displays, then custom ones.
    func resolvedGuides() -> [ResolvedGuide] {
        var result: [ResolvedGuide] = []
        if GuideSettings.showEdgeGuides {
            let sources = GuideSettings.edgeScope == .selectedDisplay
                ? physicalLayout.displays.filter { selectedDisplayIDs.contains($0.id) }
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
        if GuideSettings.showCustomGuides {
            for guide in GuideStore.shared.guides {
                result.append(ResolvedGuide(axis: guide.axis, position: guide.position, color: .systemPink, customID: guide.id))
            }
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
        guard GuideSettings.showCustomGuides, !isOverRuler(point) else { return nil }
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
            let isActive = guide.customID != nil && (guide.customID == hoverGuideID || guide.customID == guideDrag || selectedGuideIDs.contains(guide.customID!))
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

    // MARK: - Gap Measurements
    private func panelRect(_ display: PhysicalLayout.Display) -> CGRect {
        CGRect(x: display.x, y: display.y, width: display.width, height: display.height)
    }

    /// Every gap between two displays that face each other with nothing in between.
    func gapMeasurements() -> [GapMeasurement] {
        guard GuideSettings.showGapMeasurements else { return [] }
        let displays = physicalLayout.displays
        var result: [GapMeasurement] = []
        for i in displays.indices {
            for j in displays.indices where j > i {
                let a = displays[i], b = displays[j]
                let ra = panelRect(a), rb = panelRect(b)
                let key = [a.persistentID, b.persistentID].sorted().joined(separator: "|")
                let placement = GapPlacementStore.placement(for: key)

                // Side by side: they overlap in y and are separated in x.
                let lowY = max(ra.minY, rb.minY), highY = min(ra.maxY, rb.maxY)
                if highY - lowY > 0.01 {
                    let pair: (first: PhysicalLayout.Display, second: PhysicalLayout.Display, from: CGFloat, to: CGFloat)?
                    if ra.maxX < rb.minX - 0.001 { pair = (a, b, ra.maxX, rb.minX) }
                    else if rb.maxX < ra.minX - 0.001 { pair = (b, a, rb.maxX, ra.minX) }
                    else { pair = nil }
                    if let pair {
                        let y = lowY + CGFloat(placement) * (highY - lowY)
                        let between = CGRect(x: pair.from, y: lowY, width: pair.to - pair.from, height: highY - lowY)
                        if !isBlocked(between, except: [a.id, b.id]) {
                            result.append(GapMeasurement(
                                direction: .horizontal, first: pair.first.id, second: pair.second.id, gap: pair.to - pair.from,
                                start: CGPoint(x: pair.from, y: y), end: CGPoint(x: pair.to, y: y),
                                overlapLow: lowY, overlapHigh: highY, placement: placement, key: key
                            ))
                        }
                    }
                    continue
                }

                // Stacked: they overlap in x and are separated in y.
                let lowX = max(ra.minX, rb.minX), highX = min(ra.maxX, rb.maxX)
                guard highX - lowX > 0.01 else { continue }
                let pair: (first: PhysicalLayout.Display, second: PhysicalLayout.Display, from: CGFloat, to: CGFloat)?
                if ra.maxY < rb.minY - 0.001 { pair = (a, b, ra.maxY, rb.minY) }
                else if rb.maxY < ra.minY - 0.001 { pair = (b, a, rb.maxY, ra.minY) }
                else { pair = nil }
                if let pair {
                    let x = lowX + CGFloat(placement) * (highX - lowX)
                    let between = CGRect(x: lowX, y: pair.from, width: highX - lowX, height: pair.to - pair.from)
                    if !isBlocked(between, except: [a.id, b.id]) {
                        result.append(GapMeasurement(
                            direction: .vertical, first: pair.first.id, second: pair.second.id, gap: pair.to - pair.from,
                            start: CGPoint(x: x, y: pair.from), end: CGPoint(x: x, y: pair.to),
                            overlapLow: lowX, overlapHigh: highX, placement: placement, key: key
                        ))
                    }
                }
            }
        }
        return result
    }

    /// True when a third display sits inside the gap, which would make the measurement misleading.
    private func isBlocked(_ gap: CGRect, except ids: [CGDirectDisplayID]) -> Bool {
        physicalLayout.displays.contains { display in
            !ids.contains(display.id) && panelRect(display).intersects(gap)
        }
    }

    private func gapEndpoints(_ m: GapMeasurement) -> (CGPoint, CGPoint) {
        (
            CGPoint(x: m.start.x * pointsPerInch + viewOffset.x, y: m.start.y * pointsPerInch + viewOffset.y),
            CGPoint(x: m.end.x * pointsPerInch + viewOffset.x, y: m.end.y * pointsPerInch + viewOffset.y)
        )
    }

    private func gapLabel(_ m: GapMeasurement) -> NSAttributedString {
        NSAttributedString(
            string: "\(MeasurementFormat.string(Double(m.gap))) in",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white]
        )
    }

    /// The pill holding the distance, beside the arrow rather than on top of it.
    private func gapLabelRect(_ m: GapMeasurement) -> CGRect {
        let (p0, p1) = gapEndpoints(m)
        let size = gapLabel(m).size()
        let width = size.width + 12, height = size.height + 4
        let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        switch m.direction {
        case .horizontal: return CGRect(x: mid.x - width / 2, y: mid.y + 10, width: width, height: height)
        case .vertical: return CGRect(x: mid.x + 10, y: mid.y - height / 2, width: width, height: height)
        }
    }

    /// The measurement under `point` and which part of it: the quarter beside each display, or the middle.
    private func gapMeasurement(at point: CGPoint) -> (measurement: GapMeasurement, zone: GapZone)? {
        guard !isOverRuler(point) else { return nil }
        for m in gapMeasurements() {
            let (p0, p1) = gapEndpoints(m)
            let band: CGRect
            switch m.direction {
            case .horizontal: band = CGRect(x: min(p0.x, p1.x) - 3, y: p0.y - 8, width: abs(p1.x - p0.x) + 6, height: 16)
            case .vertical: band = CGRect(x: p0.x - 8, y: min(p0.y, p1.y) - 3, width: 16, height: abs(p1.y - p0.y) + 6)
            }
            let onLabel = gapLabelRect(m).contains(point)
            guard band.contains(point) || onLabel else { continue }
            // How far along the arrow the pointer is, from the first display's end (0) to the second's (1).
            let along: CGFloat
            switch m.direction {
            case .horizontal: along = p1.x == p0.x ? 0.5 : (point.x - p0.x) / (p1.x - p0.x)
            case .vertical: along = p1.y == p0.y ? 0.5 : (point.y - p0.y) / (p1.y - p0.y)
            }
            let zone: GapZone = onLabel ? .middle : (along < 0.25 ? .first : (along > 0.75 ? .second : .middle))
            return (m, zone)
        }
        return nil
    }

    /// Dragging along the gap slides the measurement; dragging across it, from either end, moves
    /// that end's display. The middle of the arrow only slides.
    private func dragGap(_ drag: GapDrag, to point: CGPoint, constrain: Bool) {
        let m = drag.measurement
        var dx = (point.x - drag.startPoint.x) / pointsPerInch
        var dy = (point.y - drag.startPoint.y) / pointsPerInch
        // Shift keeps the drag to one direction: along the gap or across it.
        if constrain { if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 } }
        let across = m.direction == .horizontal ? dx : dy
        let along = m.direction == .horizontal ? dy : dx

        // Slide the arrow within the span where the two displays face each other.
        let span = m.overlapHigh - m.overlapLow
        if span > 0 {
            let startPosition = (m.direction == .horizontal ? m.start.y : m.start.x) - m.overlapLow
            GapPlacementStore.setPlacement(Double((startPosition + along) / span), for: m.key)
        }

        didDrag = true
        // Move the display at the grabbed end without letting the displays overlap or the gap pass zero.
        guard drag.zone != .middle, let startRect = drag.startRect else { needsDisplay = true; return }
        let grabbed = drag.zone == .first ? m.first : m.second
        guard isEditable(.display(grabbed)) else { needsDisplay = true; return }
        let limited = drag.zone == .first ? min(across, m.gap) : max(across, -m.gap)
        let offset = m.direction == .horizontal ? CGSize(width: limited, height: 0) : CGSize(width: 0, height: limited)
        apply(startRect.offsetBy(dx: offset.width, dy: offset.height), to: .display(grabbed))
        needsDisplay = true
    }

    private func displayColor(_ id: CGDirectDisplayID) -> NSColor {
        physicalLayout.displays.first(where: { $0.id == id }).map { NSColor(displayHex: $0.colorHex) } ?? .systemGray
    }

    /// Gap arrows are gray. The part under the mouse takes the color of the display it would move.
    private func drawGapMeasurements() {
        for m in gapMeasurements() {
            let (p0, p1) = gapEndpoints(m)
            var activeZone: GapZone?
            if let drag = gapDrag { activeZone = drag.measurement.key == m.key ? drag.zone : nil }
            else if m.key == hoverGapKey { activeZone = hoverGapZone }
            let gray = NSColor.systemGray
            func color(for zone: GapZone) -> NSColor {
                guard activeZone == zone else { return gray }
                switch zone {
                case .first: return displayColor(m.first)
                case .second: return displayColor(m.second)
                case .middle: return NSColor.controlAccentColor
                }
            }
            let capLength: CGFloat = 16
            let arrow: CGFloat = 6
            func lerp(_ t: CGFloat) -> CGPoint { CGPoint(x: p0.x + (p1.x - p0.x) * t, y: p0.y + (p1.y - p0.y) * t) }
            let quarter0 = lerp(0.25), quarter1 = lerp(0.75)

            // One path per zone so each can be colored on its own: end bar and arrowhead, then shaft.
            func endPath(at end: CGPoint, toward inner: CGPoint) -> NSBezierPath {
                let path = NSBezierPath()
                path.lineCapStyle = .round
                switch m.direction {
                case .horizontal:
                    path.move(to: CGPoint(x: end.x, y: end.y - capLength / 2)); path.line(to: CGPoint(x: end.x, y: end.y + capLength / 2))
                    path.move(to: end); path.line(to: inner)
                    if abs(p1.x - p0.x) > arrow * 3 {
                        let step = end.x < inner.x ? arrow : -arrow
                        path.move(to: CGPoint(x: end.x + step, y: end.y + arrow)); path.line(to: end); path.line(to: CGPoint(x: end.x + step, y: end.y - arrow))
                    }
                case .vertical:
                    path.move(to: CGPoint(x: end.x - capLength / 2, y: end.y)); path.line(to: CGPoint(x: end.x + capLength / 2, y: end.y))
                    path.move(to: end); path.line(to: inner)
                    if abs(p1.y - p0.y) > arrow * 3 {
                        let step = end.y < inner.y ? arrow : -arrow
                        path.move(to: CGPoint(x: end.x + arrow, y: end.y + step)); path.line(to: end); path.line(to: CGPoint(x: end.x - arrow, y: end.y + step))
                    }
                }
                return path
            }
            let middle = NSBezierPath()
            middle.lineCapStyle = .round
            middle.move(to: quarter0); middle.line(to: quarter1)
            let parts: [(NSBezierPath, NSColor, GapZone)] = [
                (endPath(at: p0, toward: quarter0), color(for: .first), .first),
                (middle, color(for: .middle), .middle),
                (endPath(at: p1, toward: quarter1), color(for: .second), .second)
            ]
            for (path, stroke, zone) in parts {
                let isActive = activeZone == zone
                // A dark edge keeps the arrow readable on any background.
                let outline = path.copy() as! NSBezierPath
                outline.lineWidth = (isActive ? 3 : 2.25) + 2
                NSColor.black.withAlphaComponent(0.4).setStroke()
                outline.stroke()
                path.lineWidth = isActive ? 3 : 2.25
                stroke.setStroke()
                path.stroke()
            }

            let label = gapLabelRect(m)
            (activeZone == .middle ? NSColor.controlAccentColor : gray).withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: label, xRadius: 5, yRadius: 5).fill()
            gapLabel(m).draw(at: CGPoint(x: label.minX + 6, y: label.minY + 2))
        }
    }

    // MARK: - Undo
    private var undoBefore: WorkspaceSnapshot?
    private var undoName = "Edit Layout"

    func captureSnapshot() -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            displays: displays,
            layout: physicalLayout.displays,
            guides: GuideStore.shared.guides,
            reference: ImageLayerState(frame: referenceLayer.frame, isLocked: referenceLayer.isLocked),
            wallpaper: ImageLayerState(frame: wallpaperLayer.frame, isLocked: wallpaperLayer.isLocked)
        )
    }

    /// Puts everything undo covers back to `snapshot` and saves it.
    func restoreSnapshot(_ snapshot: WorkspaceSnapshot) {
        suppressDisplayRebuild = true
        displays = snapshot.displays
        suppressDisplayRebuild = false
        physicalLayout.displays = snapshot.layout
        GuideStore.shared.replaceAll(snapshot.guides)
        for (slot, state) in [(ImageLayerSlot.referenceImage, snapshot.reference), (.wallpaper, snapshot.wallpaper)] {
            if layer(slot).image != nil, let frame = state.frame {
                setFrame(frame, for: slot)
                onImageFrameChanged?(slot, frame)
            }
            if layer(slot).isLocked != state.isLocked {
                setImageLocked(state.isLocked, for: slot)
                onImageLockChanged?(slot, state.isLocked)
            }
        }
        for display in displays { syncLayoutToDisplay(id: display.displayID, save: true) }
        selectedDisplayIDs = selectedDisplayIDs.filter { id in displays.contains(where: { $0.displayID == id }) }
        selectedGuideIDs = selectedGuideIDs.filter { id in GuideStore.shared.guide(withID: id) != nil }
        onSelectionChanged?(selectedDisplayInfo())
        if let info = selectedDisplayInfo(), let item = physicalLayout.displays.first(where: { $0.id == info.displayID }) {
            onDisplayValuesChanged?(info, item.centerX, item.centerY)
        }
        needsDisplay = true
    }

    /// Ends a mouse gesture, recording it as an undo step if it changed anything.
    private func finishGesture() {
        if let before = undoBefore { UndoCenter.shared.record(undoName, before: before) }
        undoBefore = nil
    }

    // MARK: - Group Selection
    /// With several displays selected, each gets an outline in its color.
    private func drawGroupSelection() {
        guard selectedDisplayIDs.count > 1 else { return }
        for display in physicalLayout.displays where selectedDisplayIDs.contains(display.id) {
            let rect = viewRect(forPhysical: outerPhysicalRect(display)).insetBy(dx: -2, dy: -2)
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2.5
            path.setLineDash([6, 4], count: 2, phase: 0)
            NSColor.white.withAlphaComponent(0.85).setStroke()
            path.stroke()
            path.lineWidth = 1.5
            NSColor(displayHex: display.colorHex).blended(withFraction: 0.35, of: .black)?.setStroke()
            path.stroke()
        }
    }

    // MARK: - Snapping
    /// What a dragged item can snap to: positions for its panel edges and for its outer (bezel) edges.
    private struct SnapTargets {
        var guideX: [CGFloat] = [], guideY: [CGFloat] = []
        var bezelX: [CGFloat] = [], bezelY: [CGFloat] = []
        /// How far the dragged item's panel edges sit inside its outer edges; images have no bezel.
        var insets: (top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat) = (0, 0, 0, 0)
    }

    private func snapTargets(for target: EditTarget, guides: Bool, bezels: Bool) -> SnapTargets {
        var targets = SnapTargets()
        var draggedDisplay: CGDirectDisplayID?
        if case .display(let id) = target, let display = physicalLayout.displays.first(where: { $0.id == id }) {
            targets.insets = bezelInsets(display)
            draggedDisplay = id
        }
        let others = physicalLayout.displays.filter { $0.id != draggedDisplay }
        if guides {
            // Panel edges snap to custom guides and to the other displays' edges.
            if GuideSettings.showCustomGuides {
                for guide in GuideStore.shared.guides {
                    if guide.axis == .vertical { targets.guideX.append(CGFloat(guide.position)) } else { targets.guideY.append(CGFloat(guide.position)) }
                }
            }
            if GuideSettings.showEdgeGuides && GuideSettings.edgeScope == .allDisplays {
                for display in others {
                    targets.guideX += [display.x, display.right]
                    targets.guideY += [display.y, display.bottom]
                }
            }
        }
        if bezels, draggedDisplay != nil {
            // Outer edges snap to the other displays' outer edges, so bezels can touch.
            for display in others {
                let outer = outerPhysicalRect(display)
                targets.bezelX += [outer.minX, outer.maxX]
                targets.bezelY += [outer.minY, outer.maxY]
            }
        }
        return targets
    }

    /// The smallest nudge, within `tolerance`, that puts an edge on one of the targets.
    private func nudge(_ edges: [(value: CGFloat, targets: [CGFloat])], tolerance: CGFloat) -> CGFloat? {
        var best: CGFloat?
        for edge in edges {
            for target in edge.targets {
                let delta = target - edge.value
                if abs(delta) <= tolerance, abs(delta) < abs(best ?? .infinity) { best = delta }
            }
        }
        return best
    }

    /// Pulls a dragged rectangle onto nearby guides and, for displays, bezel to bezel against neighbors.
    private func snappedMove(_ rect: CGRect, target: EditTarget, guides: Bool, bezels: Bool) -> CGRect {
        guard guides || bezels else { return rect }
        let t = snapTargets(for: target, guides: guides, bezels: bezels)
        let tolerance = 8 / pointsPerInch
        var result = rect
        if let dx = nudge([
            (rect.minX + t.insets.left, t.guideX), (rect.maxX - t.insets.right, t.guideX),
            (rect.minX, t.bezelX), (rect.maxX, t.bezelX)
        ], tolerance: tolerance) { result.origin.x += dx }
        if let dy = nudge([
            (rect.minY + t.insets.bottom, t.guideY), (rect.maxY - t.insets.top, t.guideY),
            (rect.minY, t.bezelY), (rect.maxY, t.bezelY)
        ], tolerance: tolerance) { result.origin.y += dy }
        return result
    }

    /// While resizing, the pointer marks the edge being dragged, so snapping moves the pointer.
    private func snappedPointer(_ p: CGPoint, handle: GrabHandle, target: EditTarget, guides: Bool, bezels: Bool) -> CGPoint {
        guard guides || bezels else { return p }
        let t = snapTargets(for: target, guides: guides, bezels: bezels)
        let tolerance = 8 / pointsPerInch
        var result = p
        let u = handle.unit
        if u.x != 0.5 {
            // The left edge's panel is inset to its right; the right edge's to its left.
            let inset = u.x == 0 ? t.insets.left : -t.insets.right
            if let dx = nudge([(p.x + inset, t.guideX), (p.x, t.bezelX)], tolerance: tolerance) { result.x += dx }
        }
        if u.y != 0.5 {
            let inset = u.y == 0 ? t.insets.bottom : -t.insets.top
            if let dy = nudge([(p.y + inset, t.guideY), (p.y, t.bezelY)], tolerance: tolerance) { result.y += dy }
        }
        return result
    }

    // MARK: - Anchor Indicator
    private var hoverHandle: GrabHandle?
    private var lastModifiers: NSEvent.ModifierFlags = []

    /// The fixed point of a resize, with arrows in the directions the item will grow or shrink:
    /// both ways around the center by default, or toward the handle from the opposite corner with Option.
    private func drawAnchorIndicator(rect physical: CGRect, handle: GrabHandle, fromCenter: Bool, rotation turn: CGFloat = 0) {
        let u = handle.unit
        let localAnchor = fromCenter
            ? CGPoint(x: physical.midX, y: physical.midY)
            : CGPoint(x: physical.minX + (1 - u.x) * physical.width, y: physical.minY + (1 - u.y) * physical.height)
        let anchor = rotatedPoint(localAnchor, about: CGPoint(x: physical.midX, y: physical.midY), degrees: turn)
        let center = CGPoint(x: anchor.x * pointsPerInch + viewOffset.x, y: anchor.y * pointsPerInch + viewOffset.y)

        var directions: [CGPoint] = []
        if u.x != 0.5 { directions += fromCenter ? [CGPoint(x: 1, y: 0), CGPoint(x: -1, y: 0)] : [CGPoint(x: u.x == 1 ? 1 : -1, y: 0)] }
        if u.y != 0.5 { directions += fromCenter ? [CGPoint(x: 0, y: 1), CGPoint(x: 0, y: -1)] : [CGPoint(x: 0, y: u.y == 1 ? 1 : -1)] }
        // The arrows turn with the item.
        directions = directions.map { rotatedPoint($0, about: .zero, degrees: turn) }

        let arrows = NSBezierPath()
        arrows.lineCapStyle = .round
        arrows.lineJoinStyle = .round
        for d in directions {
            let tail = CGPoint(x: center.x + d.x * 11, y: center.y + d.y * 11)
            let tip = CGPoint(x: center.x + d.x * 26, y: center.y + d.y * 26)
            arrows.move(to: tail); arrows.line(to: tip)
            // An open arrowhead at the tip.
            arrows.move(to: CGPoint(x: tip.x - d.x * 5 - d.y * 4, y: tip.y - d.y * 5 - d.x * 4))
            arrows.line(to: tip)
            arrows.line(to: CGPoint(x: tip.x - d.x * 5 + d.y * 4, y: tip.y - d.y * 5 + d.x * 4))
        }
        NSColor.white.withAlphaComponent(0.9).setStroke()
        arrows.lineWidth = 4.5
        arrows.stroke()
        NSColor.controlAccentColor.setStroke()
        arrows.lineWidth = 2
        arrows.stroke()

        // The anchor itself: a ring with a dot.
        let ring = NSBezierPath(ovalIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12))
        NSColor.white.setFill()
        ring.fill()
        NSColor.controlAccentColor.setStroke()
        ring.lineWidth = 2
        ring.stroke()
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)).fill()
    }

    /// Shows the anchor while resizing, or while hovering a handle (following the modifier keys held).
    private func drawAnchorIfNeeded() {
        if dragTarget != nil, case .resize(let handle) = dragMode {
            drawAnchorIndicator(rect: dragStartRect, handle: handle, fromCenter: !lastModifiers.contains(.option), rotation: dragTarget.map { rotation(of: $0) } ?? 0)
        } else if dragTarget == nil, let hoverHandle, let target = hoverTarget ?? currentSelection, let rect = physicalOuterRect(of: target) {
            drawAnchorIndicator(rect: rect, handle: hoverHandle, fromCenter: !NSEvent.modifierFlags.contains(.option), rotation: rotation(of: target))
        }
    }

    override func flagsChanged(with event: NSEvent) {
        lastModifiers = event.modifierFlags
        needsDisplay = true
        super.flagsChanged(with: event)
    }

    // MARK: - Zoom to Fit
    /// What Zoom to Fit and Center View frame, in physical inches: the selected
    /// display, or all displays as a group (bezels included) when none is selected.
    private func focusRect() -> CGRect? {
        let targets: [PhysicalLayout.Display]
        if !selectedDisplayIDs.isEmpty {
            targets = physicalLayout.displays.filter { selectedDisplayIDs.contains($0.id) }
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
                    image: cgImage, imageRect: imageRect, rotationDegrees: wallpaperLayer.frame?.rotation ?? 0,
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
        let previous = selectedDisplayIDs
        displays = DisplayInfo.detectDisplays()
        let remaining = previous.filter { id in displays.contains(where: { $0.displayID == id }) }
        if remaining != previous {
            selectedDisplayIDs = remaining
            onSelectionChanged?(selectedDisplayInfo())
        } else if !previous.isEmpty {
            onSelectionChanged?(selectedDisplayInfo())
        }
        needsDisplay = true
    }

    // MARK: - Mouse
    /// A magnifier for zoom drags; AppKit has no public one.
    private static let magnifierCursor: NSCursor = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold).applying(NSImage.SymbolConfiguration(paletteColors: [.black, .black]))
        guard let image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "Zoom")?.withSymbolConfiguration(configuration) else { return .arrow }
        return NSCursor(image: image, hotSpot: NSPoint(x: image.size.width * 0.42, y: image.size.height * 0.42))
    }()
    private var pushedCursor = false

    private func pushCursor(_ cursor: NSCursor) {
        guard !pushedCursor else { return }
        cursor.push()
        pushedCursor = true
    }

    private func popCursor() {
        guard pushedCursor else { return }
        NSCursor.pop()
        pushedCursor = false
    }

    /// Selects a display or the reference image, or clears the selection.
    /// With `extending`, a display is added to the selection, or removed if it is already in it.
    private func select(_ target: EditTarget?, extending: Bool = false) {
        var targetsDisplay = false
        if case .display? = target { targetsDisplay = true }
        if !(extending && targetsDisplay) {
            selectedDisplayIDs = []
            selectedGuideIDs = []
        }
        selectedImage = nil
        switch target {
        case .display(let id):
            if extending {
                if selectedDisplayIDs.contains(id) { selectedDisplayIDs.remove(id) } else { selectedDisplayIDs.insert(id) }
            } else {
                selectedDisplayIDs = [id]
            }
        case .image(let slot): selectedImage = slot
        case nil: break
        }
        onSelectionChanged?(selectedDisplayInfo())
        needsDisplay = true
    }

    /// Remembers where everything selected started, so a drag can move the whole group together.
    private func captureGroup() {
        groupDisplayStart = [:]
        for id in selectedDisplayIDs {
            if let rect = physicalOuterRect(of: .display(id)) { groupDisplayStart[id] = rect }
        }
        groupGuideStart = [:]
        for id in selectedGuideIDs {
            if let guide = GuideStore.shared.guide(withID: id) { groupGuideStart[id] = guide.position }
        }
    }

    private var isGroupSelected: Bool { selectedDisplayIDs.count + selectedGuideIDs.count > 1 }

    /// Moves the rest of the group by the same amount as the item being dragged. Locked displays stay put.
    private func moveGroup(dx: CGFloat, dy: CGFloat, excludingDisplay: CGDirectDisplayID?, excludingGuide: UUID?) {
        for (id, start) in groupDisplayStart where id != excludingDisplay && isEditable(.display(id)) {
            apply(start.offsetBy(dx: dx, dy: dy), to: .display(id))
        }
        for (id, start) in groupGuideStart where id != excludingGuide {
            if let guide = GuideStore.shared.guide(withID: id) {
                GuideStore.shared.setPosition(start + Double(guide.axis == .vertical ? dx : dy), for: id)
            }
        }
    }

    override func mouseDown(
        with event: NSEvent
    ) {
        let point = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        let extending = event.modifierFlags.contains(.shift)
        undoBefore = captureSnapshot()
        undoName = "Edit Layout"
        groupDisplayStart = [:]
        groupGuideStart = [:]
        pendingCollapse = nil
        didDrag = false

        // Dragging out of a ruler creates a guide.
        if let axis = rulerAxis(at: point) {
            undoName = "Add Guide"
            GuideSettings.showCustomGuides = true
            let guide = Guide(axis: axis, position: guidePosition(for: point, axis: axis))
            GuideStore.shared.add(guide)
            select(nil)
            selectedGuideIDs = [guide.id]
            guideDrag = guide.id
            guideDragPoint = point
            pushCursor(guideCursor(axis))
            return
        }
        // Clicking a custom guide selects it (Shift adds or removes it) and drags it with the rest of the selection.
        if let guide = customGuide(at: point) {
            if extending {
                if selectedGuideIDs.contains(guide.id) { selectedGuideIDs.remove(guide.id) } else { selectedGuideIDs.insert(guide.id) }
                selectedImage = nil
                onSelectionChanged?(selectedDisplayInfo())
                needsDisplay = true
                return
            }
            if !selectedGuideIDs.contains(guide.id) {
                select(nil)
                selectedGuideIDs = [guide.id]
            }
            captureGroup()
            undoName = isGroupSelected ? "Move Selection" : "Move Guide"
            guideDrag = guide.id
            guideDragPoint = point
            pushCursor(guideCursor(guide.axis))
            return
        }
        // Dragging a gap measurement slides it along the gap, or moves the display on the grabbed side.
        if let hit = gapMeasurement(at: point) {
            var rect: CGRect?
            if hit.zone != .middle {
                let grabbed = hit.zone == .first ? hit.measurement.first : hit.measurement.second
                select(.display(grabbed))
                rect = physicalOuterRect(of: .display(grabbed))
            }
            undoName = "Move Display"
            gapDrag = GapDrag(measurement: hit.measurement, zone: hit.zone, startPoint: point, startRect: rect)
            pushCursor(gapCursor(hit.measurement, zone: hit.zone))
            return
        }

        // The lock icon is only visible (and clickable) on locked or selected displays.
        if let locked = physicalLayout.displays.reversed().first(where: {
            ($0.isLocked || selectedDisplayIDs.contains($0.id)) && lockIconRect(in: physicalRectToView($0)).contains(point)
        }) {
            undoName = locked.isLocked ? "Unlock Display" : "Lock Display"
            select(.display(locked.id))
            updateSelectedDisplay(DisplayEdit(isLocked: !locked.isLocked))
            return
        }

        // Image lock icons behave the same way.
        if let slot = imageSlots.reversed().first(where: { imageLockIconRect($0)?.contains(point) == true }) {
            undoName = layer(slot).isLocked ? "Unlock Image" : "Lock Image"
            select(.image(slot))
            let locked = !layer(slot).isLocked
            setImageLocked(locked, for: slot)
            onImageLockChanged?(slot, locked)
            return
        }

        // The knob above a selected image turns it.
        if let target = rotateHit(at: point), case .image = target, let start = physicalOuterRect(of: target) {
            select(target)
            isPanning = false
            undoName = "Rotate Image"
            dragTarget = target
            dragStartPoint = point
            dragStartRect = start
            let center = viewRect(forPhysical: start)
            dragMode = .rotate(startAngle: atan2(point.y - center.midY, point.x - center.midX), startRotation: rotation(of: target))
            pushCursor(ToolCursors.rotate)
            return
        }

        // Clicking an item selects it and starts moving it, or resizing it from a handle.
        // Shift adds a display to the selection or removes it. Clicking empty workspace
        // clears the selection and begins panning.
        if let hit = itemHit(point) {
            isPanning = false
            switch hit.target {
            case .display(let id) where hit.handle == nil && extending:
                select(hit.target, extending: true)
                guard selectedDisplayIDs.contains(id) else { return }
            case .display(let id) where hit.handle == nil && selectedDisplayIDs.contains(id) && isGroupSelected:
                // Keep the group so it can be dragged as one.
                pendingCollapse = hit.target
            default:
                select(hit.target)
            }
            guard isEditable(hit.target), let start = physicalOuterRect(of: hit.target) else { return }
            dragTarget = hit.target
            dragMode = hit.handle.map(DragMode.resize) ?? .move
            dragStartPoint = point
            dragStartRect = start
            var subject = "Display"
            if case .image = hit.target { subject = "Image" }
            if case .move = dragMode { undoName = isGroupSelected ? "Move Selection" : "Move \(subject)" } else { undoName = "Resize \(subject)" }
            if case .resize(let handle) = dragMode {
                pushCursor(resizeCursor(handle, rotation: rotation(of: hit.target)))
            } else if case .display = hit.target {
                captureGroup()
            }
            return
        }

        // Command-drag on the background zooms, keeping the selection.
        if event.modifierFlags.contains(.command) {
            pushCursor(Self.magnifierCursor)
            isZoomDragging = true
            zoomDragStart = point
            zoomDragStartZoom = zoom
            // Option zooms around the middle of the viewport instead of where the drag began.
            zoomDragAnchorPoint = event.modifierFlags.contains(.option) ? CGPoint(x: bounds.midX, y: bounds.midY) : point
            zoomDragAnchor = viewToPhysical(zoomDragAnchorPoint)
            return
        }

        select(nil)
        pushCursor(.closedHand)
        panStartPoint = point
        panStartOffset = viewOffset
        isPanning = true
    }

    override func mouseDragged(
        with event: NSEvent
    ) {
        let currentPoint = convert(event.locationInWindow, from: nil)

        if let guideDrag, let guide = GuideStore.shared.guide(withID: guideDrag) {
            let position = guidePosition(for: currentPoint, axis: guide.axis)
            GuideStore.shared.setPosition(position, for: guideDrag)
            guideDragPoint = currentPoint
            // The rest of a multiple selection travels with the guide.
            if isGroupSelected, let start = groupGuideStart[guideDrag] {
                let delta = CGFloat(position - start)
                moveGroup(dx: guide.axis == .vertical ? delta : 0, dy: guide.axis == .horizontal ? delta : 0, excludingDisplay: nil, excludingGuide: guideDrag)
            }
            didDrag = true
            return
        }

        if let gapDrag {
            dragGap(gapDrag, to: currentPoint, constrain: event.modifierFlags.contains(.shift))
            return
        }

        if let dragTarget {
            let flags = event.modifierFlags
            lastModifiers = flags
            if case .rotate(let startAngle, let startRotation) = dragMode, case .image(let slot) = dragTarget {
                let center = viewRect(forPhysical: dragStartRect)
                let angle = atan2(currentPoint.y - center.midY, currentPoint.x - center.midX)
                var degrees = Double(startRotation + (angle - startAngle) * 180 / .pi)
                // Shift snaps to 15 degree steps.
                if flags.contains(.shift) { degrees = (degrees / 15).rounded() * 15 }
                setImageRotation(ImageFrame.normalized(degrees), for: slot)
                didDrag = true
                return
            }
            // Control turns snapping the other way for as long as it is held.
            let invert = flags.contains(.control)
            let snapGuides = GuideSettings.snapToGuides != invert
            let snapBezels = GuideSettings.snapToBezels != invert
            let rect: CGRect
            switch dragMode {
            case .move:
                var dx = (currentPoint.x - dragStartPoint.x) / pointsPerInch
                var dy = (currentPoint.y - dragStartPoint.y) / pointsPerInch
                // Shift keeps the move to one direction.
                if flags.contains(.shift) { if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 } }
                rect = snappedMove(dragStartRect.offsetBy(dx: dx, dy: dy), target: dragTarget, guides: snapGuides, bezels: snapBezels)
            case .rotate:
                return
            case .resize(let handle):
                var minSize = CGSize(width: minimumItemSize, height: minimumItemSize)
                var isImage = false
                if case .display(let id) = dragTarget, let d = physicalLayout.displays.first(where: { $0.id == id }) {
                    let i = bezelInsets(d)
                    minSize = CGSize(width: i.left + i.right + minimumItemSize, height: i.top + i.bottom + minimumItemSize)
                } else if case .image = dragTarget {
                    isImage = true
                }
                // Proportional by default; Shift unlinks width and height (images keep their shape).
                let keepAspect = isImage || !flags.contains(.shift)
                // Scaling is around the center by default; Option anchors the opposite corner or edge instead.
                let fromCenter = !flags.contains(.option)
                let turn = rotation(of: dragTarget)
                if turn == 0 {
                    let pointer = snappedPointer(viewToPhysical(currentPoint), handle: handle, target: dragTarget, guides: snapGuides, bezels: snapBezels)
                    rect = resizedRect(dragStartRect, handle: handle, to: pointer, keepAspect: keepAspect, fromCenter: fromCenter, minSize: minSize)
                } else {
                    // A turned image is resized in its own frame, then moved so a fixed corner stays where it was.
                    let start = CGPoint(x: dragStartRect.midX, y: dragStartRect.midY)
                    let local = rotatedPoint(viewToPhysical(currentPoint), about: start, degrees: -turn)
                    var resized = resizedRect(dragStartRect, handle: handle, to: local, keepAspect: true, fromCenter: fromCenter, minSize: minSize)
                    if !fromCenter {
                        let u = handle.unit
                        let anchor = CGPoint(x: dragStartRect.minX + (1 - u.x) * dragStartRect.width, y: dragStartRect.minY + (1 - u.y) * dragStartRect.height)
                        let before = rotatedPoint(anchor, about: start, degrees: turn)
                        let after = rotatedPoint(anchor, about: CGPoint(x: resized.midX, y: resized.midY), degrees: turn)
                        resized = resized.offsetBy(dx: before.x - after.x, dy: before.y - after.y)
                    }
                    rect = resized
                }
            }
            apply(rect, to: dragTarget)
            // Moving one selected display moves the whole selection.
            if case .move = dragMode, case .display(let id) = dragTarget, isGroupSelected {
                moveGroup(dx: rect.minX - dragStartRect.minX, dy: rect.minY - dragStartRect.minY, excludingDisplay: id, excludingGuide: nil)
            }
            didDrag = true
            return
        }

        if isZoomDragging {
            // Dragging up zooms in, down zooms out; the point under the cursor at the start stays put.
            let newZoom = min(max(zoomDragStartZoom * exp((currentPoint.y - zoomDragStart.y) * 0.01), 0.05), 10)
            zoom = newZoom
            viewOffset = CGPoint(
                x: zoomDragAnchorPoint.x - zoomDragAnchor.x * pointsPerInch,
                y: zoomDragAnchorPoint.y - zoomDragAnchor.y * pointsPerInch
            )
            needsDisplay = true
            return
        }

        guard isPanning else {
            return
        }

        var dx = currentPoint.x - panStartPoint.x
        var dy = currentPoint.y - panStartPoint.y
        // Shift keeps the pan to one direction.
        if event.modifierFlags.contains(.shift) { if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 } }
        viewOffset = CGPoint(
            x: panStartOffset.x + dx,
            y: panStartOffset.y + dy
        )
        needsDisplay = true
    }

    /// Moves or resizes an item so its footprint (including bezel for displays) is `rect`.
    private func setImageRotation(_ degrees: Double, for slot: ImageLayerSlot) {
        guard var frame = layer(slot).frame else { return }
        frame.rotation = degrees
        setFrame(frame, for: slot)
        onImageFrameChanged?(slot, frame)
    }

    private func apply(_ rect: CGRect, to target: EditTarget) {
        switch target {
        case .image(let slot):
            let frame = ImageFrame(centerX: Double(rect.midX), centerY: Double(rect.midY), width: Double(rect.width), rotation: layer(slot).frame?.rotation ?? 0)
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
            syncLayoutToDisplay(id: id, save: false)
            needsDisplay = true
            onDisplayValuesChanged?(displays[i], physicalLayout.displays[j].centerX, physicalLayout.displays[j].centerY)
        }
    }

    override func mouseUp(
        with event: NSEvent
    ) {
        popCursor()
        defer { finishGesture() }
        if gapDrag != nil {
            gapDrag = nil
            syncSelectedLayoutToDisplay(save: true)
            needsDisplay = true
            return
        }
        if let guideDrag, let guide = GuideStore.shared.guide(withID: guideDrag) {
            // Dropping a guide back on its ruler removes it.
            let point = convert(event.locationInWindow, from: nil)
            let onRuler = guide.axis == .horizontal ? point.x <= rulerSize : point.y >= bounds.maxY - rulerSize
            if onRuler {
                GuideStore.shared.remove(guideDrag)
                selectedGuideIDs.remove(guideDrag)
            } else {
                GuideStore.shared.save()
            }
            for id in groupDisplayStart.keys { syncLayoutToDisplay(id: id, save: true) }
            self.guideDrag = nil
            needsDisplay = true
            return
        }
        isPanning = false
        isZoomDragging = false
        if case .display(let id)? = dragTarget {
            for moved in Set(groupDisplayStart.keys).union([id]) { syncLayoutToDisplay(id: moved, save: true) }
            if !groupGuideStart.isEmpty { GuideStore.shared.save() }
        }
        dragTarget = nil
        // A plain click on a member of a multiple selection narrows it to that display.
        if let pending = pendingCollapse, !didDrag { select(pending) }
        pendingCollapse = nil
        groupDisplayStart = [:]
        groupGuideStart = [:]
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
        let before = captureSnapshot()
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
        // A click on a lock icon is recorded by its mouse gesture instead.
        if undoBefore == nil { UndoCenter.shared.record("Edit Display", before: before, coalesceKey: "inspector-\(id)-\(edit.undoKey)") }
    }

    private func syncSelectedLayoutToDisplay(save: Bool) {
        guard let id = selectedDisplayID else { return }
        syncLayoutToDisplay(id: id, save: save)
    }

    /// Saves one display's size, position and appearance with the others.
    private func syncLayoutToDisplay(id: CGDirectDisplayID, save: Bool) {
        guard let item = physicalLayout.displays.first(where: { $0.id == id }), let i = displays.firstIndex(where: { $0.displayID == id }) else { return }
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
        // Zoom around the cursor, or around the middle of the viewport if the cursor is outside it
        // or Option is held.
        let location = convert(event.locationInWindow, from: nil)
        let anchor = bounds.contains(location) && !event.modifierFlags.contains(.option) ? location : CGPoint(x: bounds.midX, y: bounds.midY)
        setZoom(zoom * exp(CGFloat(event.scrollingDeltaY) * 0.01), keeping: anchor)
    }

    /// Trackpad pinch: zoom around the point between the fingers.
    override func magnify(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let anchor = bounds.contains(location) && !event.modifierFlags.contains(.option) ? location : CGPoint(x: bounds.midX, y: bounds.midY)
        setZoom(zoom * (1 + event.magnification), keeping: anchor)
    }
}
