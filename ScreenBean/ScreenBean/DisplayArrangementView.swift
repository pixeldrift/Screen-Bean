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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
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
    private func physicalPointToView(
        x: CGFloat,
        y: CGFloat
    ) -> CGPoint {
        let point =
            physicalLayout.pointInView(
                x: x,
                y: y,
                scale: pointsPerInch
            )
        return CGPoint(
            x: point.x + viewOffset.x,
            y: point.y + viewOffset.y
        )
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
        context.saveGState()
        let baseColor = Self.color(fromHex: display.colorHex)
        let light = baseColor.blended(withFraction: 0.20, of: .white) ?? baseColor
        let dark = baseColor.blended(withFraction: 0.24, of: .black) ?? baseColor
        let colors = [light.cgColor, baseColor.cgColor, dark.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
            context.saveGState()
            context.addRect(rect)
            context.clip()
            context.drawLinearGradient(gradient, start: CGPoint(x: rect.maxX, y: rect.maxY), end: CGPoint(x: rect.minX, y: rect.minY), options: [])
            context.restoreGState()
        } else {
            context.setFillColor(baseColor.cgColor)
            context.fill(rect)
        }

        context.saveGState()
        // Subtle, scale-independent-looking drop shadow around the physical frame.
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: max(3, 7 * zoom),
                         color: NSColor.black.withAlphaComponent(0.42).cgColor)
        context.setFillColor(NSColor(calibratedWhite: 0.16, alpha: 1).cgColor)
        context.fill(outerRect)
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.restoreGState()

        // A restrained metallic edge, with the dark bezel measured in physical inches.
        context.setFillColor(NSColor(calibratedWhite: 0.34, alpha: 1).cgColor)
        context.fill(outerRect)
        let innerFrame = outerRect.insetBy(dx: min(1.5, outerRect.width * 0.01),
                                           dy: min(1.5, outerRect.height * 0.01))
        context.setFillColor(NSColor(calibratedWhite: 0.09, alpha: 1).cgColor)
        context.fill(innerFrame)

        let baseColor = Self.color(fromHex: display.colorHex)
        let light = baseColor.blended(withFraction: 0.20, of: .white) ?? baseColor
        let dark = baseColor.blended(withFraction: 0.24, of: .black) ?? baseColor
        let colors = [light.cgColor, baseColor.cgColor, dark.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
            context.saveGState()
            context.addRect(rect)
            context.clip()
            context.drawLinearGradient(gradient, start: CGPoint(x: rect.maxX, y: rect.maxY),
                                       end: CGPoint(x: rect.minX, y: rect.minY), options: [])
            context.restoreGState()
        } else {
            context.setFillColor(baseColor.cgColor)
            context.fill(rect)
        }

        context.setStrokeColor(isSelected ? NSColor.controlAccentColor.cgColor : NSColor.labelColor.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(isSelected ? 2 : 1)
        context.stroke(rect)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.black
        ]
        let nameRect = CGRect(x: rect.minX + 8, y: rect.midY + 10,
                              width: max(rect.width - 16, 1), height: 20)
        display.nickname.draw(in: nameRect, withAttributes: nameAttributes)
        let sizeText = String(format: "%.1f × %.1f in", display.width, display.height)
        let sizeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.black
        ]
        let sizeRect = CGRect(x: rect.minX + 8, y: rect.midY - 12,
                              width: max(rect.width - 16, 1), height: 18)
        sizeText.draw(in: sizeRect, withAttributes: sizeAttributes)
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
            selectedDisplayID = hit.id
            onSelectionChanged?(
                displays.first(where: { $0.displayID == hit.id })
            )
            isPanning = false
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

    func updateSelectedDisplay(nickname: String? = nil, width: Double? = nil, height: Double? = nil, x: Double? = nil, y: Double? = nil, color: NSColor? = nil, uniformBezel: Bool? = nil, bezelTop: Double? = nil, bezelBottom: Double? = nil, bezelLeft: Double? = nil, bezelRight: Double? = nil) {
        guard let id = selectedDisplayID, let i = displays.firstIndex(where: { $0.displayID == id }), let j = physicalLayout.displays.firstIndex(where: { $0.id == id }) else { return }
        suppressDisplayRebuild = true
        if let nickname, !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { displays[i].nickname = nickname; physicalLayout.displays[j].nickname = nickname }
        if let width, width > 0.1 { displays[i].physicalWidthInches = width; physicalLayout.displays[j].width = width }
        if let height, height > 0.1 { displays[i].physicalHeightInches = height; physicalLayout.displays[j].height = height }
        if let x { physicalLayout.displays[j].x = x }
        if let y { physicalLayout.displays[j].y = y }
        if let color { displays[i].colorHex = Self.hex(from: color); physicalLayout.displays[j].colorHex = Self.hex(from: color) }
        if let uniformBezel { displays[i].uniformBezel = uniformBezel; physicalLayout.displays[j].uniformBezel = uniformBezel }
        if let bezelTop { displays[i].bezelTop = bezelTop; physicalLayout.displays[j].bezelTop = bezelTop }
        if let bezelBottom { displays[i].bezelBottom = bezelBottom; physicalLayout.displays[j].bezelBottom = bezelBottom }
        if let bezelLeft { displays[i].bezelLeft = bezelLeft; physicalLayout.displays[j].bezelLeft = bezelLeft }
        if let bezelRight { displays[i].bezelRight = bezelRight; physicalLayout.displays[j].bezelRight = bezelRight }
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
        if save { DisplayConfigurationStore.shared.save(configuration) }
    }

    private static func color(fromHex hex: String) -> NSColor {
        let v = UInt64(hex, radix: 16) ?? 0x28B7B0
        return NSColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }

    private static func hex(from color: NSColor) -> String {
        guard let c = color.usingColorSpace(.deviceRGB) else { return "28B7B0" }
        return String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
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
