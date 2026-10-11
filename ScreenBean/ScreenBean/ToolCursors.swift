//
//  ToolCursors.swift
//  ScreenBean
//
//  Directional cursors drawn in code, so resize handles, guides and gap arrows can show
//  an arrow pointing the way the drag will go, including diagonals AppKit doesn't offer.
//

import Cocoa

enum ToolCursors {
    private static var cache: [Int: NSCursor] = [:]

    /// A double-headed arrow along `angle` degrees: 0 is left-right, 90 is up-down,
    /// 45 runs from lower left to upper right, 135 from upper left to lower right.
    static func resize(angle: CGFloat) -> NSCursor {
        var degrees = angle.truncatingRemainder(dividingBy: 180)
        if degrees < 0 { degrees += 180 }
        let key = Int(degrees.rounded()) % 180
        if let cursor = cache[key] { return cursor }

        let size = NSSize(width: 28, height: 28)
        let radians = CGFloat(key) * .pi / 180
        let image = NSImage(size: size, flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let along = CGPoint(x: cos(radians), y: sin(radians))
            // A point `t` along the arrow and `n` to its side.
            func point(_ t: CGFloat, _ n: CGFloat) -> CGPoint {
                CGPoint(x: center.x + along.x * t - along.y * n, y: center.y + along.y * t + along.x * n)
            }
            let half: CGFloat = 10
            let path = NSBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: point(-half, 0)); path.line(to: point(half, 0))
            for side: CGFloat in [-1, 1] {
                path.move(to: point(side * (half - 5), 4)); path.line(to: point(side * half, 0)); path.line(to: point(side * (half - 5), -4))
            }
            NSColor.white.setStroke(); path.lineWidth = 5; path.stroke()
            NSColor.black.setStroke(); path.lineWidth = 2; path.stroke()
            return true
        }
        let cursor = NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
        cache[key] = cursor
        return cursor
    }

    /// A circular arrow for rotating.
    static let rotate: NSCursor = {
        let size = NSSize(width: 28, height: 28)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 8
            let path = NSBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.appendArc(withCenter: center, radius: radius, startAngle: 40, endAngle: 320)
            // Arrowhead at the end of the arc.
            let end = CGPoint(x: center.x + radius * cos(320 * .pi / 180), y: center.y + radius * sin(320 * .pi / 180))
            path.move(to: CGPoint(x: end.x - 5, y: end.y + 1)); path.line(to: end); path.line(to: CGPoint(x: end.x + 1, y: end.y + 5))
            NSColor.white.setStroke(); path.lineWidth = 5; path.stroke()
            NSColor.black.setStroke(); path.lineWidth = 2; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }()
}
