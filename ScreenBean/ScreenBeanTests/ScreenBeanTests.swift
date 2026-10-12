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

    @Test func understandsMetricUnitsTypedAfterANumber() {
        #expect(MeasurementFormat.parse("2.54 cm") == 1)
        #expect(MeasurementFormat.parse("25.4mm") == 1)
        #expect(MeasurementFormat.parse("-5.08 centimeters") == -2)
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

struct AspectRatioTests {
    @Test func namesFamiliarShapes() {
        #expect(AspectRatio.string(16.0 / 9.0) == "16:9")
        #expect(AspectRatio.string(9.0 / 16.0) == "9:16")
        #expect(AspectRatio.string(1.43) == "1.43:1")
    }

    @Test func readsRatiosAsTyped() {
        #expect(AspectRatio.parse("16:9") == 16.0 / 9.0)
        #expect(AspectRatio.parse("16 x 9") == 16.0 / 9.0)
        #expect(AspectRatio.parse("1.5") == 1.5)
        #expect(AspectRatio.parse("wide") == nil)
        #expect(AspectRatio.parse("0:9") == nil)
    }
}

struct ReferenceAlignmentTests {
    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    /// Four corners marked on an upright photo: the image is scaled and shifted, not turned.
    @Test func cornersScaleAndShift() throws {
        // A 1000 x 500 photo; the display fills (100,100) to (300,200) in it (y down) and is 10 x 5 inches at the origin.
        let marks = [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100), CGPoint(x: 300, y: 200), CGPoint(x: 100, y: 200)]
        let targets = [CGPoint(x: 0, y: 5), CGPoint(x: 10, y: 5), CGPoint(x: 10, y: 0), CGPoint(x: 0, y: 0)]
        let frame = try #require(ReferenceAlignment.fitPoints(imagePoints: marks, imageSize: CGSize(width: 1000, height: 500), targets: targets))
        #expect(close(frame.width, 50))
        #expect(close(frame.rotation, 0))
        #expect(close(frame.centerX, 20))
        #expect(close(frame.centerY, -2.5))
    }

    /// An image whose corners were marked on a display that is turned a quarter turn needs a 90 degree rotation.
    @Test func cornersFindTheTurn() throws {
        let marks = [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0), CGPoint(x: 200, y: 100), CGPoint(x: 0, y: 100)]
        // The same corners after a quarter turn counterclockwise about the center, which sits at (10, 20).
        let targets = [CGPoint(x: -40, y: -80), CGPoint(x: -40, y: 120), CGPoint(x: 60, y: 120), CGPoint(x: 60, y: -80)]
        let frame = try #require(ReferenceAlignment.fitPoints(imagePoints: marks, imageSize: CGSize(width: 200, height: 100), targets: targets))
        #expect(close(frame.rotation, 90))
        #expect(close(frame.width, 200))
        #expect(close(frame.centerX, 10))
        #expect(close(frame.centerY, 20))
    }

    /// Four points clicked in any order are sorted into top-left, top-right, bottom-right, bottom-left.
    @Test func cornersSortThemselves() {
        // Clicked as bottom-right, top-left, bottom-left, top-right (y down).
        let clicked = [CGPoint(x: 300, y: 200), CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 200), CGPoint(x: 300, y: 100)]
        #expect(ReferenceAlignment.cornerOrder(of: clicked) == [1, 3, 0, 2])
        #expect(ReferenceAlignment.cornerOrder(of: Array(clicked.prefix(3))) == nil)
    }

    /// A slightly turned display still sorts the same way.
    @Test func cornersSortWhenTilted() {
        let clicked = [CGPoint(x: 120, y: 90), CGPoint(x: 310, y: 120), CGPoint(x: 290, y: 220), CGPoint(x: 100, y: 190)]
        #expect(ReferenceAlignment.cornerOrder(of: clicked) == [0, 1, 2, 3])
    }

    /// Measuring a line only changes the size.
    @Test func measurementOnlyScales() throws {
        let current = ImageFrame(centerX: 3, centerY: -4, width: 10, rotation: 20, stretch: 1.2, flipHorizontal: true)
        let frame = try #require(ReferenceAlignment.scaled(
            toMeasure: CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50), imageSize: CGSize(width: 100, height: 100), length: 20, current: current))
        #expect(close(frame.width, 20))
        #expect(frame.centerX == 3 && frame.centerY == -4)
        #expect(frame.rotation == 20 && frame.stretch == 1.2 && frame.flipHorizontal)
    }
}
