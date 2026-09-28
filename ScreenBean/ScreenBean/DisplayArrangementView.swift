import Cocoa

var displays: [DisplayInfo] = []

class DisplayArrangementView: NSView {
    var displays: [DisplayInfo] = [] {
        didSet {
            updateDisplayViews()
            setNeedsDisplay(bounds)  // trigger redraw when displays change
        }
    }

    private let scaleFactor: CGFloat = 0.1 // consistent scale factor

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)

        guard !displays.isEmpty else { return }

        // Compute bounding rect for all displays in scaled coordinates
        let displayRects = displays.map { display -> CGRect in
            let origin = CGPoint(x: CGFloat(display.positionX) * scaleFactor,
                                 y: CGFloat(display.positionY) * scaleFactor)
            let size = CGSize(width: display.physicalWidthInches * scaleFactor,
                              height: display.physicalHeightInches * scaleFactor)
            return CGRect(origin: origin, size: size)
        }

        let unionRect = displayRects.reduce(CGRect.null) { $0.union($1) }
        let totalCanvasHeight = unionRect.height

        for display in displays {
            // Calculate scaled origin
            let origin = CGPoint(x: CGFloat(display.positionX) * scaleFactor,
                                 y: CGFloat(display.positionY) * scaleFactor)
            let size = CGSize(width: display.physicalWidthInches * scaleFactor,
                              height: display.physicalHeightInches * scaleFactor)

            // Flip Y coordinate so origin (0,0) is bottom-left instead of top-left
            let flippedY = totalCanvasHeight - origin.y - size.height
            let rect = CGRect(x: origin.x, y: flippedY, width: size.width, height: size.height)

            // Draw the display rectangle
            context.setFillColor(NSColor.systemTeal.cgColor)
            context.fill(rect)

            // Draw display info like nickname, etc.
            drawDisplay(display, in: context, rect: rect)
        }
    }

    private func updateDisplayViews() {
        
        // Remove existing DisplayView subviews before adding new ones
        subviews.forEach { $0.removeFromSuperview() }

        guard !displays.isEmpty else { return }

        // Compute bounding rect for all displays (same as in draw)
        let displayRects = displays.map { display -> CGRect in
            let origin = CGPoint(x: CGFloat(display.positionX) * scaleFactor,
                                 y: CGFloat(display.positionY) * scaleFactor)
            let size = CGSize(width: display.physicalWidthInches * scaleFactor,
                              height: display.physicalHeightInches * scaleFactor)
            return CGRect(origin: origin, size: size)
        }
        let unionRect = displayRects.reduce(CGRect.null) { $0.union($1) }
        let totalCanvasHeight = unionRect.height

        // Create and add a DisplayView for each display
        for display in displays {
            let origin = CGPoint(x: CGFloat(display.positionX) * scaleFactor,
                                 y: CGFloat(display.positionY) * scaleFactor)
            let size = CGSize(width: display.physicalWidthInches * scaleFactor,
                              height: display.physicalHeightInches * scaleFactor)

            let flippedY = totalCanvasHeight - origin.y - size.height

            let displayView = DisplayView(info: display)
            displayView.frame = CGRect(origin: CGPoint(x: origin.x, y: flippedY),
                                       size: size)
            addSubview(displayView)
        }
    }

    func drawDisplay(_ display: DisplayInfo, in context: CGContext, rect: CGRect) {
        // Draw the display's label centered within the rect
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.black
        ]

        let text = display.nickname
        let textRect = CGRect(x: rect.origin.x, y: rect.midY - 8, width: rect.width, height: 16)
        text.draw(in: textRect, withAttributes: attrs)
    }
}
