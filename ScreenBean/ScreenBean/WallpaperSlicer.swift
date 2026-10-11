//
//  WallpaperSlicer.swift
//  ScreenBean
//
//  Cuts one wallpaper placed in the physical workspace into a separate image
//  for each display, at that display's native resolution.
//

import Cocoa

/// One display's share of the wallpaper.
struct WallpaperSlice {
    let displayID: CGDirectDisplayID
    let persistentID: String
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
    let image: CGImage
    /// True for a planned display, which has no screen to apply to.
    var isVirtual = false
}

/// Everything needed to export or apply the wallpaper.
struct WallpaperExport {
    let slices: [WallpaperSlice]
    /// Pixels per physical inch in the source image.
    let imagePixelsPerInch: Double
    /// Pixels per inch of the sharpest display.
    let neededPixelsPerInch: Double

    /// True when the displays are sharper than the image, so it gets enlarged.
    var isUpscaled: Bool { imagePixelsPerInch < neededPixelsPerInch * 0.95 }
}

enum WallpaperSlicer {

    /// Where the wallpaper lands in a display's pixel grid. Both spaces have their origin
    /// at the bottom left, so physical inches map straight onto pixels.
    static func pixelRect(imageRect: CGRect, panelRect: CGRect, pixelSize: CGSize) -> CGRect {
        let scaleX = pixelSize.width / panelRect.width
        let scaleY = pixelSize.height / panelRect.height
        return CGRect(
            x: (imageRect.minX - panelRect.minX) * scaleX,
            y: (imageRect.minY - panelRect.minY) * scaleY,
            width: imageRect.width * scaleX,
            height: imageRect.height * scaleY
        )
    }

    /// Renders the part of the wallpaper under one display. Areas the wallpaper doesn't reach are black.
    static func render(image: CGImage, imageRect: CGRect, rotationDegrees: Double = 0, flipHorizontal: Bool = false, flipVertical: Bool = false, panelRect: CGRect, pixelWidth: Int, pixelHeight: Int) -> CGImage? {
        guard pixelWidth > 0, pixelHeight > 0, panelRect.width > 0, panelRect.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.interpolationQuality = .high
        let target = pixelRect(imageRect: imageRect, panelRect: panelRect, pixelSize: CGSize(width: pixelWidth, height: pixelHeight))
        if rotationDegrees == 0 && !flipHorizontal && !flipVertical {
            context.draw(image, in: target)
        } else {
            // The image is flipped, then turned, about its own center.
            context.saveGState()
            context.translateBy(x: target.midX, y: target.midY)
            context.rotate(by: CGFloat(rotationDegrees) * .pi / 180)
            context.scaleBy(x: flipHorizontal ? -1 : 1, y: flipVertical ? -1 : 1)
            context.draw(image, in: CGRect(x: -target.width / 2, y: -target.height / 2, width: target.width, height: target.height))
            context.restoreGState()
        }
        return context.makeImage()
    }
}
