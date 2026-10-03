//
//  DisplayArrangementView.swift
//  ScreenBean
//
import Cocoa
class DisplayArrangementView: NSView {
    var displays: [DisplayInfo] = [] {
        didSet {
            rebuildPhysicalLayout()
            scaleToFit()
            needsDisplay = true
        }
    }
    private var physicalLayout = PhysicalLayout()
    // MARK: - Workspace Camera
    /// Number of view points used to represent one physical inch
    /// at the default zoom level.
    private let basePointsPerInch: CGFloat = 20.0
    /// Current workspace zoom.
    private var zoom: CGFloat = 1.0
    /// Workspace position in view coordinates.
    private var viewOffset = CGPoint.zero
    /// Used while panning the workspace.
    private var panStartPoint = CGPoint.zero
    private var panStartOffset = CGPoint.zero
    private var isPanning = false
    // MARK: - Setup
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scaleToFit()
    }
    override func resizeSubviews(
        withOldSize oldSize: NSSize
    ) {
        super.resizeSubviews(withOldSize: oldSize)
        scaleToFit()
    }
    // MARK: - Layout
    private func rebuildPhysicalLayout() {
        guard !displays.isEmpty else {
            physicalLayout = PhysicalLayout()
            return
        }
        var physicalDisplays: [PhysicalLayout.Display] = []
        let referenceDisplay = displays[0]
        let referencePixelWidth = max(
            CGFloat(referenceDisplay.pixelWidth),
            1
        )
        let referencePhysicalWidth = max(
            CGFloat(referenceDisplay.physicalWidthInches),
            0.1
        )
        let inchesPerMacUnit =
            referencePhysicalWidth /
            referencePixelWidth
        let referenceX =
            CGFloat(referenceDisplay.positionX)
        let referenceY =
            CGFloat(referenceDisplay.positionY)
        for display in displays {
            let pixelX =
                CGFloat(display.positionX)
            let pixelY =
                CGFloat(display.positionY)
            let physicalX =
                (pixelX - referenceX) *
                inchesPerMacUnit
            let physicalY =
                (pixelY - referenceY) *
                inchesPerMacUnit
            let physicalDisplay =
                PhysicalLayout.Display(
                    id: display.displayID,
                    nickname: display.nickname,
                    x: physicalX,
                    y: physicalY,
                    width: CGFloat(
                        display.physicalWidthInches
                    ),
                    height: CGFloat(
                        display.physicalHeightInches
                    )
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
        let gridSpacingInches: CGFloat = 6.0
        let spacing =
            gridSpacingInches *
            pointsPerInch
        guard spacing > 2 else {
            return
        }
        let startX =
            viewOffset.x.truncatingRemainder(
                dividingBy: spacing
            )
        let startY =
            viewOffset.y.truncatingRemainder(
                dividingBy: spacing
            )
        context.saveGState()
        context.setStrokeColor(
            NSColor.separatorColor
                .withAlphaComponent(0.25)
                .cgColor
        )
        context.setLineWidth(1)
        var x = startX
        while x < bounds.width {
            context.move(
                to: CGPoint(
                    x: x,
                    y: 0
                )
            )
            context.addLine(
                to: CGPoint(
                    x: x,
                    y: bounds.height
                )
            )
            x += spacing
        }
        var y = startY
        while y < bounds.height {
            context.move(
                to: CGPoint(
                    x: 0,
                    y: y
                )
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
                .withAlphaComponent(0.75)
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
    // MARK: - Scale to Fit
    func scaleToFit() {
        guard !physicalLayout.displays.isEmpty,
              bounds.width > 0,
              bounds.height > 0
        else {
            return
        }
        let padding: CGFloat = 80
        let availableWidth =
            max(
                bounds.width - padding,
                1
            )
        let availableHeight =
            max(
                bounds.height - padding,
                1
            )
        let widthScale =
            availableWidth /
            max(
                physicalLayout.width *
                    basePointsPerInch,
                1
            )
        let heightScale =
            availableHeight /
            max(
                physicalLayout.height *
                    basePointsPerInch,
                1
            )
        zoom = min(
            widthScale,
            heightScale
        )
        zoom = max(
            zoom,
            0.05
        )
        centerView()
        needsDisplay = true
    }
    // MARK: - Center View
    func centerView() {
        guard !physicalLayout.displays.isEmpty else {
            viewOffset = CGPoint(
                x: bounds.midX,
                y: bounds.midY
            )
            needsDisplay = true
            return
        }
        let layoutWidth =
            physicalLayout.width *
            pointsPerInch
        let layoutHeight =
            physicalLayout.height *
            pointsPerInch
        viewOffset = CGPoint(
            x:
                (bounds.width -
                 layoutWidth) / 2 -
                physicalLayout.minX *
                pointsPerInch,
            y:
                (bounds.height -
                 layoutHeight) / 2 -
                physicalLayout.minY *
                pointsPerInch
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