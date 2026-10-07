//
//  DisplayArrangementView.swift
//  ScreenBean
//
import Cocoa

class DisplayArrangementView: NSView {
    var displays: [DisplayInfo] = [] {
        didSet {
            rebuildPhysicalLayout()
            needsDisplay = true
        }
    }
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
    private var hasInitializedView = false
    
    // MARK: - Setup
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard window != nil else {
            return
        }
    }
    
    override func resizeSubviews(
        withOldSize oldSize: NSSize
    ) {
        super.resizeSubviews(withOldSize: oldSize)

    }
    
    override func layout() {
        super.layout()

        guard !hasInitializedView,
              !physicalLayout.displays.isEmpty,
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }

        hasInitializedView = true

        zoomToFit(initialZoomFactor: 0.5)
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

            let physicalDisplay =
                PhysicalLayout.Display(
                    id: display.displayID,
                    nickname: display.nickname,
                    x: physicalX,
                    y: physicalY,
                    width: physicalWidth,
                    height: physicalHeight
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
                rect: rect
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
        rect: CGRect
    ) {
        context.saveGState()
        context.setFillColor(
            NSColor.systemTeal
                .withAlphaComponent(1)
                .cgColor
        )
        context.fill(rect)
        context.setStrokeColor(
            NSColor.labelColor.cgColor
        )
        context.setLineWidth(2)
        context.stroke(rect)
        context.restoreGState()
        let paragraphStyle =
            NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let nameAttributes:
            [NSAttributedString.Key: Any] = [
                .font:
                    NSFont.systemFont(
                        ofSize: 14
                    ),
                .paragraphStyle:
                    paragraphStyle,
                .foregroundColor:
                    NSColor.black
            ]
        let nameRect = CGRect(
            x: rect.minX + 8,
            y: rect.midY + 10,
            width: max(
                rect.width - 16,
                1
            ),
            height: 20
        )
        display.nickname.draw(
            in: nameRect,
            withAttributes:
                nameAttributes
        )
        let sizeText = String(
            format: "%.1f × %.1f in",
            display.width,
            display.height
        )
        let sizeAttributes:
            [NSAttributedString.Key: Any] = [
                .font:
                    NSFont.systemFont(
                        ofSize: 11
                    ),
                .paragraphStyle:
                    paragraphStyle,
                .foregroundColor:
                    NSColor.black
            ]
        let sizeRect = CGRect(
            x: rect.minX + 8,
            y: rect.midY - 12,
            width: max(
                rect.width - 16,
                1
            ),
            height: 18
        )
        sizeText.draw(
            in: sizeRect,
            withAttributes:
                sizeAttributes
        )
    }
    
    // MARK: - Zoom to Fit
    @objc func zoomToFit(
        initialZoomFactor: CGFloat = 1.0
    ) {
        guard physicalLayout.width > 0,
              physicalLayout.height > 0 else {
            return
        }
        
        print("VIEW:", bounds.width, bounds.height)
        print("LAYOUT:", physicalLayout.width, physicalLayout.height)
        print("BASE PPI:", basePointsPerInch)
        
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

        zoom =
            fitZoom * initialZoomFactor

        centerView()
    }

    // MARK: - Center View
    @objc func centerView() {
        let topInset: CGFloat = 40
        let bottomInset: CGFloat = 60

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
        panStartPoint =
            convert(
                event.locationInWindow,
                from: nil
            )
        panStartOffset =
            viewOffset
        isPanning = true
    }
    override func mouseDragged(
        with event: NSEvent
    ) {
        guard isPanning else {
            return
        }
        let currentPoint =
            convert(
                event.locationInWindow,
                from: nil
            )
        let dx =
            currentPoint.x -
            panStartPoint.x
        let dy =
            currentPoint.y -
            panStartPoint.y
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
