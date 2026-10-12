//
//  LayoutTemplate.swift
//  ScreenBean
//
//  A flat picture of the display layout at the wallpaper's own scale, to open in an image
//  editor and design a spanned wallpaper over. Each display's screen is drawn where it sits,
//  with its name and sizes; the gaps and bezels between screens are left empty.
//

import Cocoa

struct LayoutTemplate {
    struct Panel {
        var label: String
        var name: String
        /// The screen in physical inches; the origin is its lower-left corner.
        var rect: CGRect
        var pixelWidth: Int
        var pixelHeight: Int
        var colorHex: String
    }

    var panels: [Panel]

    /// The smallest rectangle holding every screen.
    var bounds: CGRect { panels.dropFirst().reduce(panels.first?.rect ?? .zero) { $0.union($1.rect) } }

    /// Pixels per inch of the sharpest display, so that display is drawn at its native resolution.
    /// Reduced if the whole image would be too large to save.
    var pixelsPerInch: Double {
        let sharpest = panels.map { Double($0.pixelWidth) / max(Double($0.rect.width), 0.01) }.max() ?? 72
        let longest = max(Double(bounds.width), Double(bounds.height), 0.01)
        return min(max(sharpest, 1), 16000 / longest)
    }

    var pixelSize: (width: Int, height: Int) {
        (max(Int((Double(bounds.width) * pixelsPerInch).rounded()), 1), max(Int((Double(bounds.height) * pixelsPerInch).rounded()), 1))
    }

    /// A panel's rectangle in image pixels, measured from the lower-left corner.
    private func pixelRect(_ panel: Panel) -> CGRect {
        let ppi = CGFloat(pixelsPerInch)
        return CGRect(x: (panel.rect.minX - bounds.minX) * ppi, y: (panel.rect.minY - bounds.minY) * ppi, width: panel.rect.width * ppi, height: panel.rect.height * ppi)
    }

    private func detail(_ panel: Panel) -> String {
        "\(panel.pixelWidth) × \(panel.pixelHeight) px  ·  " + MeasurementFormat.pair(Double(panel.rect.width), Double(panel.rect.height))
    }

    // MARK: - PNG

    func pngData() -> Data? {
        guard !panels.isEmpty else { return nil }
        let size = pixelSize
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size.width, pixelsHigh: size.height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        for panel in panels { draw(panel) }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private func draw(_ panel: Panel) {
        let rect = pixelRect(panel)
        let base = min(rect.width, rect.height)
        let color = NSColor(displayHex: panel.colorHex)
        (color.blended(withFraction: 0.45, of: .white) ?? color).setFill()
        rect.fill()

        // A grid of one inch (or one centimeter), so sizes can be read straight off the image.
        let ppi = CGFloat(pixelsPerInch)
        let cell = CGFloat(MeasurementFormat.inchesPerUnit)
        let step = ppi * cell
        let grid = NSBezierPath()
        var x = (ceil(panel.rect.minX / cell) * cell - panel.rect.minX) * ppi
        while x < rect.width { grid.move(to: CGPoint(x: rect.minX + x, y: rect.minY)); grid.line(to: CGPoint(x: rect.minX + x, y: rect.maxY)); x += step }
        var y = (ceil(panel.rect.minY / cell) * cell - panel.rect.minY) * ppi
        while y < rect.height { grid.move(to: CGPoint(x: rect.minX, y: rect.minY + y)); grid.line(to: CGPoint(x: rect.maxX, y: rect.minY + y)); y += step }
        grid.lineWidth = max(1, base / 600)
        NSColor.black.withAlphaComponent(0.12).setStroke()
        grid.stroke()

        // Corner to corner, so the center and the proportions are easy to find.
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: rect.minX, y: rect.minY)); cross.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
        cross.move(to: CGPoint(x: rect.minX, y: rect.maxY)); cross.line(to: CGPoint(x: rect.maxX, y: rect.minY))
        cross.lineWidth = max(1, base / 500)
        NSColor.black.withAlphaComponent(0.25).setStroke()
        cross.stroke()

        let edge = NSBezierPath(rect: rect.insetBy(dx: base / 400, dy: base / 400))
        edge.lineWidth = max(2, base / 200)
        NSColor.black.withAlphaComponent(0.8).setStroke()
        edge.stroke()

        func text(_ string: String, size: CGFloat, weight: NSFont.Weight, at center: CGPoint, alpha: CGFloat) {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: NSColor.black.withAlphaComponent(alpha)]
            let attributed = NSAttributedString(string: string, attributes: attributes)
            let measured = attributed.size()
            attributed.draw(at: CGPoint(x: center.x - measured.width / 2, y: center.y - measured.height / 2))
        }
        text(panel.label, size: base * 0.4, weight: .bold, at: CGPoint(x: rect.midX, y: rect.midY + base * 0.06), alpha: 0.35)
        let small = max(base * 0.045, 12)
        text(panel.name, size: small * 1.3, weight: .semibold, at: CGPoint(x: rect.midX, y: rect.minY + base * 0.2), alpha: 0.75)
        text(detail(panel), size: small, weight: .regular, at: CGPoint(x: rect.midX, y: rect.minY + base * 0.2 - small * 1.8), alpha: 0.7)
    }

    // MARK: - SVG

    /// The same picture as a vector drawing, one pixel to a unit of the view box.
    func svg() -> String? {
        guard !panels.isEmpty else { return nil }
        let size = pixelSize
        let ppi = pixelsPerInch
        func number(_ value: CGFloat) -> String { String(format: "%.2f", Double(value)) }
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(size.width)\" height=\"\(size.height)\" viewBox=\"0 0 \(size.width) \(size.height)\">\n"
        out += "  <!-- Screen Bean layout template: \(String(format: "%.2f", ppi)) pixels per inch. Gaps and bezels are left empty. -->\n"
        for (index, panel) in panels.enumerated() {
            // SVG's y axis points down; the layout's points up.
            let p = pixelRect(panel)
            let top = CGFloat(size.height) - p.maxY
            let base = min(p.width, p.height)
            let color = NSColor(displayHex: panel.colorHex)
            let fill = "#" + (color.blended(withFraction: 0.45, of: .white) ?? color).displayHex
            let small = max(base * 0.045, 12)
            let centerX = p.midX
            out += "  <g id=\"display-\(index + 1)\">\n"
            out += "    <rect x=\"\(number(p.minX))\" y=\"\(number(top))\" width=\"\(number(p.width))\" height=\"\(number(p.height))\" fill=\"\(fill)\" stroke=\"#000000\" stroke-opacity=\"0.8\" stroke-width=\"\(number(max(2, base / 200)))\"/>\n"
            out += "    <path d=\"M\(number(p.minX)) \(number(top)) L\(number(p.maxX)) \(number(top + p.height)) M\(number(p.minX)) \(number(top + p.height)) L\(number(p.maxX)) \(number(top))\" stroke=\"#000000\" stroke-opacity=\"0.25\" stroke-width=\"\(number(max(1, base / 500)))\" fill=\"none\"/>\n"
            let letterY = top + p.height / 2 - base * 0.06
            out += "    <text x=\"\(number(centerX))\" y=\"\(number(letterY))\" font-family=\"Helvetica, Arial, sans-serif\" font-weight=\"700\" font-size=\"\(number(base * 0.4))\" fill=\"#000000\" fill-opacity=\"0.35\" text-anchor=\"middle\" dominant-baseline=\"central\">\(escape(panel.label))</text>\n"
            let nameY = top + p.height - base * 0.2
            out += "    <text x=\"\(number(centerX))\" y=\"\(number(nameY))\" font-family=\"Helvetica, Arial, sans-serif\" font-weight=\"600\" font-size=\"\(number(small * 1.3))\" fill=\"#000000\" fill-opacity=\"0.75\" text-anchor=\"middle\">\(escape(panel.name))</text>\n"
            out += "    <text x=\"\(number(centerX))\" y=\"\(number(nameY + small * 1.8))\" font-family=\"Helvetica, Arial, sans-serif\" font-size=\"\(number(small))\" fill=\"#000000\" fill-opacity=\"0.7\" text-anchor=\"middle\">\(escape(detail(panel)))</text>\n"
            out += "  </g>\n"
        }
        out += "</svg>\n"
        return out
    }
}
