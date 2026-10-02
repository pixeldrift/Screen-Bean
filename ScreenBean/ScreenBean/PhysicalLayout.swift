//
//  PhysicalLayout.swift
//  ScreenBean
//
//  Created by Nathan Pizar on 10/1/26.
//

import Cocoa
import CoreGraphics

/// The physical coordinate system used by Screen Bean.
///
/// 1.0 unit = 1 physical inch.
///
/// This is not related to macOS screen coordinates
/// or the size of the Screen Bean window.
///
struct PhysicalLayout {

    // MARK: - Display

    struct Display {
        let id: CGDirectDisplayID
        let nickname: String

        /// Position of the upper-left corner in physical inches.
        var x: CGFloat
        var y: CGFloat

        /// Physical dimensions in inches.
        var width: CGFloat
        var height: CGFloat

        /// Rotation in degrees.
        var rotation: CGFloat = 0

        var right: CGFloat {
            x + width
        }

        var bottom: CGFloat {
            y + height
        }

        var centerX: CGFloat {
            x + width / 2
        }

        var centerY: CGFloat {
            y + height / 2
        }
    }

    // MARK: - Layout

    var displays: [Display]

    init(displays: [Display] = []) {
        self.displays = displays
    }

    /// The leftmost physical edge of the entire arrangement.
    var minX: CGFloat {
        displays.map(\.x).min() ?? 0
    }

    /// The topmost physical edge of the entire arrangement.
    var minY: CGFloat {
        displays.map(\.y).min() ?? 0
    }

    /// The rightmost physical edge of the entire arrangement.
    var maxX: CGFloat {
        displays.map(\.right).max() ?? 0
    }

    /// The bottommost physical edge of the entire arrangement.
    var maxY: CGFloat {
        displays.map(\.bottom).max() ?? 0
    }

    var width: CGFloat {
        maxX - minX
    }

    var height: CGFloat {
        maxY - minY
    }

    // MARK: - Coordinate Conversion

    /// Converts a point from Screen Bean physical coordinates
    /// into view coordinates.
    ///
    /// `scale` is pixels/points per physical inch.
    func pointInView(
        x: CGFloat,
        y: CGFloat,
        scale: CGFloat
    ) -> CGPoint {

        CGPoint(
            x: (x - minX) * scale,
            y: (y - minY) * scale
        )
    }

    /// Returns the rectangle for a display in view coordinates.
    func rectInView(
        for display: Display,
        scale: CGFloat
    ) -> CGRect {

        CGRect(
            x: (display.x - minX) * scale,
            y: (display.y - minY) * scale,
            width: display.width * scale,
            height: display.height * scale
        )
    }

    // MARK: - Layout Information

    /// Returns the horizontal distance between two displays.
    ///
    /// A negative value means they overlap.
    /// Zero means their edges touch.
    func horizontalGap(
        between first: Display,
        and second: Display
    ) -> CGFloat {

        if first.right <= second.x {
            return second.x - first.right
        }

        if second.right <= first.x {
            return first.x - second.right
        }

        return -min(first.right, second.right)
            + max(first.x, second.x)
    }

    /// Returns the vertical distance between two displays.
    ///
    /// A negative value means they overlap.
    /// Zero means their edges touch.
    func verticalGap(
        between first: Display,
        and second: Display
    ) -> CGFloat {

        if first.bottom <= second.y {
            return second.y - first.bottom
        }

        if second.bottom <= first.y {
            return first.y - second.bottom
        }

        return -min(first.bottom, second.bottom)
            + max(first.y, second.y)
    }
}
