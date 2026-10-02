//
//  DisplayArrangementView.swift
//  ScreenBean
//

import Cocoa

class DisplayArrangementView: NSView {

    var displays: [DisplayInfo] = [] {
        didSet {
            rebuildPhysicalLayout()
            setNeedsDisplay(bounds)
        }
    }

    private var physicalLayout = PhysicalLayout()

    /// Points/pixels used to represent one physical inch in the
    /// Screen Bean workspace.
    private let pointsPerInch: CGFloat = 20.0

    // MARK: - Layout

    private func rebuildPhysicalLayout() {

        guard !displays.isEmpty else {
            physicalLayout = PhysicalLayout()
            return
        }

        var physicalDisplays: [PhysicalLayout.Display] = []

        // Use the first display as our physical origin.
        let referenceDisplay = displays[0]

        let referencePixelWidth = max(
            CGFloat(referenceDisplay.pixelWidth),
            1
        )

        let referencePhysicalWidth = max(
            CGFloat(referenceDisplay.physicalWidthInches),
            0.1
        )

        // How many physical inches does one Mac coordinate unit represent?
        let inchesPerMacUnit =
            referencePhysicalWidth / referencePixelWidth

        let referenceX = CGFloat(referenceDisplay.positionX)
        let referenceY = CGFloat(referenceDisplay.positionY)

        for display in displays {

            let pixelX = CGFloat(display.positionX)
            let pixelY = CGFloat(display.positionY)

            let physicalX =
                (pixelX - referenceX) * inchesPerMacUnit

            let physicalY =
                (pixelY - referenceY) * inchesPerMacUnit

            let physicalDisplay = PhysicalLayout.Display(
                id: display.displayID,
                nickname: display.nickname,
                x: physicalX,
                y: physicalY,
                width: CGFloat(display.physicalWidthInches),
                height: CGFloat(display.physicalHeightInches)
            )

            physicalDisplays.append(physicalDisplay)
        }

        physicalLayout = PhysicalLayout(
            displays: physicalDisplays
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {

        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        context.clear(bounds)

        guard !physicalLayout.displays.isEmpty else {
            return
        }

        let scale = pointsPerInch

        /*
         Center the entire physical arrangement in the window.
        */

        let layoutWidth = physicalLayout.width * scale
        let layoutHeight = physicalLayout.height * scale

        let offsetX = (bounds.width - layoutWidth) / 2
        let offsetY = (bounds.height - layoutHeight) / 2

        for display in physicalLayout.displays {

            let rect = physicalLayout.rectInView(
                for: display,
                scale: scale
            )

            let finalRect = rect.offsetBy(
                dx: offsetX,
                dy: offsetY
            )

            // Display body
            context.setFillColor(
                NSColor.systemTeal.cgColor
            )

            context.fill(finalRect)

            // Display outline
            context.setStrokeColor(
                NSColor.labelColor.cgColor
            )

            context.setLineWidth(2)

            context.stroke(finalRect)

            // Display label
            drawDisplay(
                display,
                in: context,
                rect: finalRect
            )
        }
    }

    // MARK: - Labels

    private func drawDisplay(
        _ display: PhysicalLayout.Display,
        in context: CGContext,
        rect: CGRect
    ) {

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.black
        ]

        let textRect = CGRect(
            x: rect.minX,
            y: rect.midY - 8,
            width: rect.width,
            height: 16
        )

        display.nickname.draw(
            in: textRect,
            withAttributes: attrs
        )
    }
}
