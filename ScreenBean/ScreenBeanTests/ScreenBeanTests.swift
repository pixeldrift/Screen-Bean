//
//  ScreenBeanTests.swift
//  ScreenBeanTests
//
//  Created by Nathan Pizar on 5/21/25.
//

import Testing
import CoreGraphics
@testable import ScreenBean

struct ScreenBeanTests {

    /// A wallpaper exactly covering a display fills its whole pixel grid.
    @Test func wallpaperCoveringDisplayFillsPixels() {
        let rect = WallpaperSlicer.pixelRect(
            imageRect: CGRect(x: 0, y: 0, width: 20, height: 10),
            panelRect: CGRect(x: 0, y: 0, width: 20, height: 10),
            pixelSize: CGSize(width: 2000, height: 1000)
        )
        #expect(rect == CGRect(x: 0, y: 0, width: 2000, height: 1000))
    }

    /// A display to the right of the wallpaper's left edge sees the image shifted left.
    @Test func displayOffsetShiftsWallpaper() {
        let rect = WallpaperSlicer.pixelRect(
            imageRect: CGRect(x: 0, y: 0, width: 40, height: 10),
            panelRect: CGRect(x: 20, y: 0, width: 20, height: 10),
            pixelSize: CGSize(width: 2000, height: 1000)
        )
        #expect(rect == CGRect(x: -2000, y: 0, width: 4000, height: 1000))
    }

    /// Pixel density differences between displays change how many pixels an inch gets.
    @Test func denserDisplayGetsMorePixelsPerInch() {
        let image = CGRect(x: 0, y: 0, width: 10, height: 10)
        let sparse = WallpaperSlicer.pixelRect(imageRect: image, panelRect: image, pixelSize: CGSize(width: 1000, height: 1000))
        let dense = WallpaperSlicer.pixelRect(imageRect: image, panelRect: image, pixelSize: CGSize(width: 3000, height: 3000))
        #expect(dense.width == sparse.width * 3)
    }
}
