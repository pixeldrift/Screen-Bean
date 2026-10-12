//
//  DisplayIdentity.swift
//  ScreenBean
//
//  What identifies a display on screen: its letter, color, name and sizes.
//  Shared by the virtual displays in the workspace and the overlays on the real ones.
//

import Cocoa

struct DisplayIdentity {
    let id: CGDirectDisplayID
    let label: String
    let colorHex: String
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
    let widthInches: Double
    let heightInches: Double
    let isPrimary: Bool

    /// A, B, C ... then A1, B1 ... for a display's position in the list.
    static func label(forIndex index: Int) -> String {
        let letter = String(UnicodeScalar(UInt8(65 + index % 26)))
        return index < 26 ? letter : "\(letter)\(index / 26)"
    }

    /// Identities in the same order as the displays, so letters match the workspace.
    static func identities(for displays: [DisplayInfo]) -> [DisplayIdentity] {
        displays.enumerated().map { index, d in
            DisplayIdentity(
                id: d.displayID, label: label(forIndex: index), colorHex: d.colorHex, name: d.nickname,
                pixelWidth: d.pixelWidth, pixelHeight: d.pixelHeight,
                widthInches: d.physicalWidthInches, heightInches: d.physicalHeightInches,
                isPrimary: d.isPrimary
            )
        }
    }

    var resolutionText: String { "\(pixelWidth) × \(pixelHeight) px" }
    var sizeText: String { MeasurementFormat.pair(widthInches, heightInches) }
}

extension NSScreen {
    /// The screen showing the given display, if it is active.
    static func screen(forDisplayID id: CGDirectDisplayID) -> NSScreen? {
        screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
    }
}
