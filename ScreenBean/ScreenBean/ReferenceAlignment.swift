//
//  ReferenceAlignment.swift
//  ScreenBean
//
//  Works out the size and place of a reference photo in the workspace from marks made on it: the four
//  corners of a display, or a line of known length (which sets only the scale). Photos are taken at an
//  angle through a lens, so the fit is a uniform scale, a turn and a shift: the best match, not a perfect one.
//
//  Marks are in image points with the origin at the top left and y pointing down, the way a photo
//  is seen. Workspace positions are in inches with y pointing up.
//

import CoreGraphics
import Foundation

enum ReferenceAlignment {
    private static func yUp(_ point: CGPoint, imageHeight: CGFloat) -> CGPoint { CGPoint(x: point.x, y: imageHeight - point.y) }

    private static func turned(_ point: CGPoint, by radians: Double) -> CGPoint {
        CGPoint(x: point.x * cos(radians) - point.y * sin(radians), y: point.x * sin(radians) + point.y * cos(radians))
    }

    // MARK: - Corners

    /// Which of four clicked points is the top-left, top-right, bottom-right and bottom-left corner, as indices into
    /// `points` (origin at the top left, y down). The points can be clicked in any order; the photo is assumed to be
    /// roughly upright, with the top of the display toward the top of the photo.
    static func cornerOrder(of points: [CGPoint]) -> [Int]? {
        guard points.count == 4 else { return nil }
        let center = CGPoint(x: points.map(\.x).reduce(0, +) / 4, y: points.map(\.y).reduce(0, +) / 4)
        // With y pointing down, increasing angle runs clockwise.
        let clockwise = points.indices.sorted {
            atan2(points[$0].y - center.y, points[$0].x - center.x) < atan2(points[$1].y - center.y, points[$1].x - center.x)
        }
        // The top-left corner is the one nearest the photo's top-left.
        guard let first = clockwise.indices.min(by: { points[clockwise[$0]].x + points[clockwise[$0]].y < points[clockwise[$1]].x + points[clockwise[$1]].y }) else { return nil }
        return (0..<4).map { clockwise[(first + $0) % 4] }
    }

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

    // MARK: - Measurement

    /// Sizes the image so the line between the two marks is `length` inches long. Only the size changes: the image
    /// keeps its center, turn, stretch and flips.
    static func scaled(toMeasure first: CGPoint, _ second: CGPoint, imageSize: CGSize, length: Double, current: ImageFrame) -> ImageFrame? {
        guard imageSize.width > 0, length > 0 else { return nil }
        let pixelLength = Double(hypot(second.x - first.x, second.y - first.y))
        guard pixelLength > 0 else { return nil }
        var frame = current
        frame.width = Double(imageSize.width) * length / pixelLength
        return frame
    }
}
