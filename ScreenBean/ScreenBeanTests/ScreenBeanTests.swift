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

    // MARK: - Measurement format

    @Test func parsesFractionsAndDecimals() {
        #expect(MeasurementFormat.parse("23 1/8") == 23.125)
        #expect(MeasurementFormat.parse("23-1/8") == 23.125)
        #expect(MeasurementFormat.parse("1/2") == 0.5)
        #expect(MeasurementFormat.parse("-1 1/2") == -1.5)
        #expect(MeasurementFormat.parse("23.5") == 23.5)
        #expect(MeasurementFormat.parse("13 3/4\"") == 13.75)
        #expect(MeasurementFormat.parse("24 in") == 24)
    }

    @Test func rejectsNonMeasurements() {
        #expect(MeasurementFormat.parse("") == nil)
        #expect(MeasurementFormat.parse("abc") == nil)
        #expect(MeasurementFormat.parse("1/0") == nil)
        #expect(MeasurementFormat.parse("1 2 3") == nil)
    }

    @Test func formatsFractionsToNearestSixteenth() {
        #expect(MeasurementFormat.fractionString(23.125) == "23 1/8")
        #expect(MeasurementFormat.fractionString(0.5) == "1/2")
        #expect(MeasurementFormat.fractionString(24) == "24")
        #expect(MeasurementFormat.fractionString(13.4) == "13 3/8")
        #expect(MeasurementFormat.fractionString(-1.5) == "-1 1/2")
        #expect(MeasurementFormat.fractionString(0.01) == "0")
    }

    @Test func formatsDecimalsWithoutTrailingZeros() {
        #expect(MeasurementFormat.decimalString(23.5) == "23.5")
        #expect(MeasurementFormat.decimalString(0.0625) == "0.0625")
        #expect(MeasurementFormat.decimalString(24) == "24.0")
    }
}
