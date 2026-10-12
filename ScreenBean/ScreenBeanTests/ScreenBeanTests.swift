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

    /// A line along a display's top edge sets the scale and puts the line's middle on the edge's middle.
    @Test func lineAlongTopEdge() throws {
        let rect = CGRect(x: 0, y: 0, width: 20, height: 10)
        let current = ImageFrame(centerX: 0, centerY: 0, width: 30)
        let frame = try #require(ReferenceAlignment.fitLine(
            from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 100), imageSize: CGSize(width: 1000, height: 500),
            length: 10, target: .edge(.top, rect), current: current))
        #expect(close(frame.width, 50))
        #expect(close(frame.rotation, 0))
        #expect(close(frame.centerX, 25))
        #expect(close(frame.centerY, 2.5))
    }

    /// A slightly tilted line along an edge turns the image level.
    @Test func lineLevelsTheImage() throws {
        let rect = CGRect(x: 0, y: 0, width: 20, height: 10)
        let current = ImageFrame(centerX: 0, centerY: 0, width: 30)
        // Up and to the right in the photo by about 5.7 degrees.
        let frame = try #require(ReferenceAlignment.fitLine(
            from: CGPoint(x: 100, y: 120), to: CGPoint(x: 300, y: 100), imageSize: CGSize(width: 1000, height: 500),
            length: 10, target: .edge(.bottom, rect), current: current))
        #expect(frame.rotation < 0 && frame.rotation > -10)
    }

    /// With only a length, the image scales about the line's middle and keeps its turn.
    @Test func lineScaleOnlyKeepsItsPlace() throws {
        // A 100 x 100 image, 10 inches wide, centered at the origin. A line across its middle.
        let current = ImageFrame(centerX: 0, centerY: 0, width: 10)
        let frame = try #require(ReferenceAlignment.fitLine(
            from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50), imageSize: CGSize(width: 100, height: 100),
            length: 20, target: .scaleOnly, current: current))
        #expect(close(frame.width, 20))
        #expect(close(frame.centerX, 0))
        #expect(close(frame.centerY, 0))
    }
}
