//
//  DisplayDefaults.swift
//  ScreenBean
//
//  Shared defaults and color helpers for display appearance.
//

import Cocoa

enum DisplayDefaults {
    /// Colors handed out to displays in order, unless the user picks one.
    static let palette = [
        "A8D5CE", // soft teal
        "B9C5EB", // periwinkle
        "F2C4A7", // peach
        "BED5AC", // sage
        "D3BCE8", // lilac
        "E9B9C2", // rose
        "E9D995", // butter
        "A9CDE8"  // sky
    ]

    /// The default color for the display at `index`, cycling through the palette.
    static func paletteColor(at index: Int) -> String {
        palette[((index % palette.count) + palette.count) % palette.count]
    }

    static let colorHex = palette[0]

    /// The single default color used before the palette existed.
    static let legacyColorHex = "28B7B0"
    static let bezelColorHex = "4A4A4A"
    static let bezelInches = 0.25
}

extension NSColor {
    /// Creates a color from an "RRGGBB" hex string, falling back to the default display color.
    convenience init(displayHex hex: String) {
        let v = UInt64(hex, radix: 16) ?? UInt64(DisplayDefaults.colorHex, radix: 16)!
        self.init(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }

    /// The color as an "RRGGBB" hex string.
    var displayHex: String {
        guard let c = usingColorSpace(.deviceRGB) else { return DisplayDefaults.colorHex }
        return String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

/// The diagonal gradient used to fill a display, in the workspace and on the real screen.
enum DisplayGradient {
    static func make(hex: String) -> CGGradient? {
        let base = NSColor(displayHex: hex)
        let light = base.blended(withFraction: 0.45, of: .white) ?? base
        let dark = base.blended(withFraction: 0.50, of: .black) ?? base
        return CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [light.cgColor, base.cgColor, dark.cgColor] as CFArray,
            locations: [0, 0.5, 1]
        )
    }
}
