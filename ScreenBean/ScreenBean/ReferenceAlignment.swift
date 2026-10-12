//
//  ReferenceAlignment.swift
//  ScreenBean
//
//  Works out where a reference photo goes in the workspace from marks made on it: either the four
//  corners of a display, or a line of known length. Photos are taken at an angle through a lens, so
//  the fit is a uniform scale, a turn and a shift: the best match, not a perfect one.
//
//  Marks are in image points with the origin at the top left and y pointing down, the way a photo
//  is seen. Workspace positions are in inches with y pointing up.
//

import CoreGraphics
import Foundation

enum ReferenceAlignment {
    enum Edge { case top, bottom, left, right }

    /// What a marked line stands for.
    enum LineTarget {
        /// The line runs along this edge of a display's screen (the rectangle, in workspace inches).
        case edge(Edge, CGRect)
        /// Only the scale is known; the line keeps its place and the image keeps its turn.
        case scaleOnly
    }

    private static func yUp(_ point: CGPoint, imageHeight: CGFloat) -> CGPoint { CGPoint(x: point.x, y: imageHeight - point.y) }

    private static func turned(_ point: CGPoint, by radians: Double) -> CGPoint {
        CGPoint(x: point.x * cos(radians) - point.y * sin(radians), y: point.x * sin(radians) + point.y * cos(radians))
    }

    /// An angle in degrees folded into -90...90, since a line has no direction.
    private static func foldedToHalfTurn(_ degrees: Double) -> Double {
        var d = ImageFrame.normalized(degrees)
        if d > 90 { d -= 180 } else if d <= -90 { d += 180 }
        return d
    }

    // MARK: - Corners

    /// Places the image so each marked point lands as near as possible on its target (for a display, its four
    /// corners in the same order). Needs at least two points.
    static func fitPoints(imagePoints: [CGPoint], imageSize: CGSize, targets: [CGPoint]) -> ImageFrame? {
        guard imagePoints.count == targets.count, imagePoints.count >= 2, imageSize.width > 0, imageSize.height > 0 else { return nil }
        let marks = imagePoints.map { yUp($0, imageHeight: imageSize.height) }
        let count = CGFloat(marks.count)
        let markMean = CGPoint(x: marks.map(\.x).reduce(0, +) / count, y: marks.map(\.y).reduce(0, +) / count)
        let targetMean = CGPoint(x: targets.map(\.x).reduce(0, +) / count, y: targets.map(\.y).reduce(0, +) / count)

        var dot = 0.0, cross = 0.0, norm = 0.0
        for index in marks.indices {
            let a = CGPoint(x: marks[index].x - markMean.x, y: marks[index].y - markMean.y)
            let b = CGPoint(x: targets[index].x - targetMean.x, y: targets[index].y - targetMean.y)
            dot += Double(a.x * b.x + a.y * b.y)
            cross += Double(a.x * b.y - a.y * b.x)
            norm += Double(a.x * a.x + a.y * a.y)
        }
        guard norm > 0 else { return nil }
        let theta = atan2(cross, dot)
        let scale = hypot(cross, dot) / norm
        guard scale > 0 else { return nil }

        // The marks' average has to land on the targets' average.
        let imageCenter = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let offset = turned(CGPoint(x: (markMean.x - imageCenter.x) * scale, y: (markMean.y - imageCenter.y) * scale), by: theta)
        return ImageFrame(
            centerX: Double(targetMean.x - offset.x), centerY: Double(targetMean.y - offset.y),
            width: Double(imageSize.width) * scale, rotation: ImageFrame.normalized(theta * 180 / .pi)
        )
    }

    // MARK: - Line

    /// Scales the image so the line between the two marks is `length` inches long. For an edge, the image is also
    /// turned so the line runs along it, with the line's middle on the edge's middle.
    static func fitLine(from first: CGPoint, to second: CGPoint, imageSize: CGSize, length: Double, target: LineTarget, current: ImageFrame) -> ImageFrame? {
        guard imageSize.width > 0, imageSize.height > 0, length > 0 else { return nil }
        let a = yUp(first, imageHeight: imageSize.height), b = yUp(second, imageHeight: imageSize.height)
        let along = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let pixelLength = Double(hypot(along.x, along.y))
        guard pixelLength > 0 else { return nil }
        let scale = length / pixelLength

        let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let local = CGPoint(x: middle.x - imageSize.width / 2, y: middle.y - imageSize.height / 2)
        let lineAngle = Double(atan2(along.y, along.x)) * 180 / .pi

        let degrees: Double
        let anchor: CGPoint
        switch target {
        case .edge(let edge, let rect):
            switch edge {
            case .top: degrees = foldedToHalfTurn(-lineAngle); anchor = CGPoint(x: rect.midX, y: rect.maxY)
            case .bottom: degrees = foldedToHalfTurn(-lineAngle); anchor = CGPoint(x: rect.midX, y: rect.minY)
            case .left: degrees = foldedToHalfTurn(90 - lineAngle); anchor = CGPoint(x: rect.minX, y: rect.midY)
            case .right: degrees = foldedToHalfTurn(90 - lineAngle); anchor = CGPoint(x: rect.maxX, y: rect.midY)
            }
        case .scaleOnly:
            // Where the line's middle is now stays where it is.
            degrees = current.rotation
            let before = Double(current.width) / Double(imageSize.width)
            let shown = turned(CGPoint(x: local.x * before, y: local.y * before * current.stretch), by: current.rotation * .pi / 180)
            anchor = CGPoint(x: current.centerX + shown.x, y: current.centerY + shown.y)
        }
        let placed = turned(CGPoint(x: local.x * scale, y: local.y * scale), by: degrees * .pi / 180)
        return ImageFrame(
            centerX: Double(anchor.x - placed.x), centerY: Double(anchor.y - placed.y),
            width: Double(imageSize.width) * scale, rotation: ImageFrame.normalized(degrees)
        )
    }
}
