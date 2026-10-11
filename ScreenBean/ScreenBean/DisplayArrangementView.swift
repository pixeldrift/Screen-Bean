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

    /// An image drawn in the workspace, sized to the width of the arrangement.
    /// Its blend sets the opacity and whether it draws below or above the displays.
    struct ImageLayer {
        var image: NSImage?
        var blend = ImageLayerBlend(value: 0)
    }

    /// Photo or plan drawn as a layout reference.
    var referenceLayer = ImageLayer() { didSet { needsDisplay = true } }
    /// One image spanned across the whole arrangement.
    var wallpaperLayer = ImageLayer() { didSet { needsDisplay = true } }
    private var imageLayers: [ImageLayer] { [referenceLayer, wallpaperLayer] }
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
    private var draggingDisplayID: CGDirectDisplayID?
    private var dragStartPoint = CGPoint.zero
    private var dragStartDisplayOrigin = CGPoint.zero
    private var hasInitializedView = false
    

    
    // MARK: - Setup

    override func layout() {
        super.layout()

        guard !displays.isEmpty,
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }

        if !hasInitializedView {
            hasInitializedView = true
            zoomToFit(initialZoomFactor: 0.5)
            return
        }

        centerView()
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

            let physicalCenterX =
                -(pixelX - referenceCenterX) *
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
            let physicalDisplay = PhysicalLayout.Display(
                id: display.displayID, nickname: display.nickname,
                persistentID: display.persistentID, colorHex: display.colorHex,
                uniformBezel: display.uniformBezel,
                bezelTop: CGFloat(display.bezelTop), bezelBottom: CGFloat(display.bezelBottom),
                bezelLeft: CGFloat(display.bezelLeft), bezelRight: CGFloat(display.bezelRight),
                showBezel: display.showBezel, isLocked: display.isLocked,
                x: CGFloat(saved?.xInches ?? Double(physicalX)),
                y: CGFloat(saved?.yInches ?? Double(physicalY)),
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
        for layer in imageLayers where !layer.blend.aboveDisplays { drawImageLayer(layer) }
        for display in physicalLayout.displays {
            let rect =
                physicalRectToView(
                    display
                )
            drawDisplay(
                display,
                in: context,
                rect: rect,
                isSelected: display.id == selectedDisplayID
            )
        }
        for layer in imageLayers where layer.blend.aboveDisplays { drawImageLayer(layer) }
    }

    // MARK: - Image Layers
    /// Draws an image layer, anchored to the arrangement's top-left corner
    /// and scaled to the arrangement's width.
    private func drawImageLayer(_ layer: ImageLayer) {
        guard let image = layer.image,
              layer.blend.opacity > 0,
              image.size.width > 0, image.size.height > 0,
              physicalLayout.width > 0 else { return }
        let width = physicalLayout.width
        let height = width * image.size.height / image.size.width
        let rect = CGRect(
            x: physicalLayout.minX * pointsPerInch + viewOffset.x,
            y: physicalLayout.minY * pointsPerInch + viewOffset.y,
            width: width * pointsPerInch,
            height: height * pointsPerInch
        )
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: CGFloat(layer.blend.opacity), respectFlipped: true, hints: nil)
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
        isSelected: Bool
    ) {
        // Bezel thickness is stored in physical inches and scales with the canvas.
        let scale = pointsPerInch
        func bezel(_ value: CGFloat) -> CGFloat { display.showBezel ? max(0, value) * scale : 0 }
        let top = bezel(display.bezelTop)
        let bottom = bezel(display.uniformBezel ? display.bezelTop : display.bezelBottom)
        let left = bezel(display.uniformBezel ? display.bezelTop : display.bezelLeft)
        let right = bezel(display.uniformBezel ? display.bezelTop : display.bezelRight)
        let outerRect = CGRect(
            x: rect.minX - left,
            y: rect.minY - bottom,
            width: rect.width + left + right,
            height: rect.height + top + bottom
        )
        let frameColor = NSColor(calibratedWhite: 0.30, alpha: 1)

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
        if display.showBezel, let frameGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [NSColor(calibratedWhite: 0.38, alpha: 1).cgColor, NSColor(calibratedWhite: 0.20, alpha: 1).cgColor] as CFArray,
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
        let light = baseColor.blended(withFraction: 0.45, of: .white) ?? baseColor
        let dark = baseColor.blended(withFraction: 0.50, of: .black) ?? baseColor
        let colors = [light.cgColor, baseColor.cgColor, dark.cgColor] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 0.5, 1]
        ) {
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

        if isSelected {
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(2)
            context.stroke(outerRect.insetBy(dx: -1, dy: -1))
        }

        drawLockIcon(for: display, in: rect, isSelected: isSelected)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.black
        ]
        let nameRect = CGRect(
            x: rect.minX + 8,
            y: rect.midY + 10,
            width: max(rect.width - 16, 1),
            height: 20
        )
        display.nickname.draw(in: nameRect, withAttributes: nameAttributes)

        let sizeText = String(format: "%.1f × %.1f in", display.width, display.height)
        let sizeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.black
        ]
        let sizeRect = CGRect(
            x: rect.minX + 8,
            y: rect.midY - 12,
            width: max(rect.width - 16, 1),
            height: 18
        )
        sizeText.draw(in: sizeRect, withAttributes: sizeAttributes)
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
        let name = display.isLocked ? "lock.fill" : "lock.open.fill"
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: display.isLocked ? "Locked" : "Unlocked")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [NSColor.white.withAlphaComponent(display.isLocked ? 0.9 : 0.55)]))
        else { return }
        symbol.draw(in: lockIconRect(in: rect))
    }

    // MARK: - Zoom to Fit
    @objc func zoomToFit(
        initialZoomFactor: CGFloat = 1.0
    ) {
        guard physicalLayout.width > 0,
              physicalLayout.height > 0 else {
            return
        }
                
        let sideInset: CGFloat = 40
        let topInset: CGFloat = 40
        let bottomInset: CGFloat = 60

        let availableWidth =
            bounds.width - sideInset * 2

        let availableHeight =
            bounds.height - topInset - bottomInset

        guard availableWidth > 0,
              availableHeight > 0 else {
            return
        }

        let zoomX =
            availableWidth /
            (physicalLayout.width * basePointsPerInch)

        let zoomY =
            availableHeight /
            (physicalLayout.height * basePointsPerInch)

        let fitZoom =
            min(zoomX, zoomY)
        
        zoom = fitZoom * initialZoomFactor
        
        centerView()
        
    }
    
    @objc func zoomToFitFromButton() {
        zoomToFit(initialZoomFactor: 1.0)
    }

    // MARK: - Center View
    @objc func centerView() {
        let topInset: CGFloat = 60
        let bottomInset: CGFloat = 40

        let usableCenterY =
            topInset +
            (bounds.height - topInset - bottomInset) / 2

        viewOffset = CGPoint(
            x: bounds.midX,
            y: usableCenterY
        )

        needsDisplay = true
    }
    
    // MARK: - Mouse Pan
    override func mouseDown(
        with event: NSEvent
    ) {
        let point = convert(
            event.locationInWindow,
            from: nil
        )

        // Clicking a display selects it. Clicking empty workspace
        // clears the selection and begins panning.
        if let hit = physicalLayout.displays.reversed().first(where: {
            physicalRectToView($0).contains(point)
        }) {
            // The lock icon is only visible (and clickable) on locked or already-selected displays.
            let lockIsVisible = hit.isLocked || selectedDisplayID == hit.id
            selectedDisplayID = hit.id
            onSelectionChanged?(
                displays.first(where: { $0.displayID == hit.id })
            )
            isPanning = false
            if lockIsVisible, lockIconRect(in: physicalRectToView(hit)).contains(point) {
                updateSelectedDisplay(DisplayEdit(isLocked: !hit.isLocked))
                return
            }
            if hit.isLocked { needsDisplay = true; return }
            draggingDisplayID = hit.id
            dragStartPoint = point
            if let selectedLayoutDisplay = physicalLayout.displays.first(where: { $0.id == hit.id }) {
                dragStartDisplayOrigin = CGPoint(
                    x: selectedLayoutDisplay.x,
                    y: selectedLayoutDisplay.y
                )
            }
            needsDisplay = true
            return
        }

        selectedDisplayID = nil
        onSelectionChanged?(nil)
        panStartPoint = point
        panStartOffset = viewOffset
        isPanning = true
        needsDisplay = true
    }
    override func mouseDragged(
        with event: NSEvent
    ) {
        let currentPoint = convert(event.locationInWindow, from: nil)

        if let draggingDisplayID {
            let dx = (currentPoint.x - dragStartPoint.x) / pointsPerInch
            let dy = (currentPoint.y - dragStartPoint.y) / pointsPerInch

            guard let index = physicalLayout.displays.firstIndex(where: { $0.id == draggingDisplayID }) else {
                return
            }

            physicalLayout.displays[index].x = dragStartDisplayOrigin.x + dx
            physicalLayout.displays[index].y = dragStartDisplayOrigin.y + dy
            syncSelectedLayoutToDisplay(save: false)
            needsDisplay = true
            if let info = selectedDisplayInfo() {
                onDisplayValuesChanged?(info, physicalLayout.displays[index].x, physicalLayout.displays[index].y)
            }
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
    override func mouseUp(
        with event: NSEvent
    ) {
        isPanning = false
        if draggingDisplayID != nil {
            syncSelectedLayoutToDisplay(save: true)
            if let info = selectedDisplayInfo(), let item = physicalLayout.displays.first(where: { $0.id == info.displayID }) {
                onDisplayValuesChanged?(info, item.x, item.y)
            }
        }
        draggingDisplayID = nil
    }
    

    func selectedDisplayInfo() -> DisplayInfo? {
        guard let id = selectedDisplayID else { return nil }
        return displays.first(where: { $0.displayID == id })
    }

    func selectedPosition() -> (x: CGFloat, y: CGFloat)? {
        guard let id = selectedDisplayID, let item = physicalLayout.displays.first(where: { $0.id == id }) else { return nil }
        return (item.x, item.y)
    }

    func updateSelectedDisplay(_ edit: DisplayEdit) {
        guard let id = selectedDisplayID, let i = displays.firstIndex(where: { $0.displayID == id }), let j = physicalLayout.displays.firstIndex(where: { $0.id == id }) else { return }
        // A locked display only accepts the change that unlocks it.
        if displays[i].isLocked && edit.isLocked == nil { return }
        suppressDisplayRebuild = true
        if let nickname = edit.nickname, !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { displays[i].nickname = nickname; physicalLayout.displays[j].nickname = nickname }
        if let width = edit.width, width > 0.1 { displays[i].physicalWidthInches = width; physicalLayout.displays[j].width = width }
        if let height = edit.height, height > 0.1 { displays[i].physicalHeightInches = height; physicalLayout.displays[j].height = height }
        if let x = edit.x { physicalLayout.displays[j].x = x }
        if let y = edit.y { physicalLayout.displays[j].y = y }
        if let color = edit.color { displays[i].colorHex = color.displayHex; physicalLayout.displays[j].colorHex = color.displayHex }
        if let uniformBezel = edit.uniformBezel { displays[i].uniformBezel = uniformBezel; physicalLayout.displays[j].uniformBezel = uniformBezel }
        if let bezelTop = edit.bezelTop { displays[i].bezelTop = bezelTop; physicalLayout.displays[j].bezelTop = CGFloat(bezelTop) }
        if let bezelBottom = edit.bezelBottom { displays[i].bezelBottom = bezelBottom; physicalLayout.displays[j].bezelBottom = CGFloat(bezelBottom) }
        if let bezelLeft = edit.bezelLeft { displays[i].bezelLeft = bezelLeft; physicalLayout.displays[j].bezelLeft = CGFloat(bezelLeft) }
        if let bezelRight = edit.bezelRight { displays[i].bezelRight = bezelRight; physicalLayout.displays[j].bezelRight = CGFloat(bezelRight) }
        if let showBezel = edit.showBezel { displays[i].showBezel = showBezel; physicalLayout.displays[j].showBezel = showBezel }
        if let isLocked = edit.isLocked { displays[i].isLocked = isLocked; physicalLayout.displays[j].isLocked = isLocked }
        suppressDisplayRebuild = false
        syncSelectedLayoutToDisplay(save: true)
        needsDisplay = true
        onDisplayValuesChanged?(displays[i], physicalLayout.displays[j].x, physicalLayout.displays[j].y)
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
        configuration.showBezel = displays[i].showBezel; configuration.isLocked = displays[i].isLocked
        if save { DisplayConfigurationStore.shared.save(configuration) }
    }

    // MARK: - Scroll Zoom
    override func scrollWheel(
        with event: NSEvent
    ) {
        let zoomAmount =
            1.0 +
            CGFloat(event.scrollingDeltaY) *
            0.01
        zoom *= zoomAmount
        zoom = min(
            max(zoom, 0.05),
            10.0
        )
        needsDisplay = true
    }
}
