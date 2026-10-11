//
//  DisplayDefaults.swift
//  ScreenBean
//
//  Shared defaults and color helpers for display appearance.
//

import Cocoa

enum DisplayDefaults {
    static let colorHex = "28B7B0"
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
