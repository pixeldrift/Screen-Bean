//
//  DisplayInfo.swift
//  ScreenBean
//
//  Created by Nathan Pizar on 5/21/25.
//

import Cocoa
import CoreGraphics

struct DisplayInfo {

    var displayID: CGDirectDisplayID

    /// Apple's persistent UUID for this physical display.
    var persistentID: String

    var nickname: String

    var pixelWidth: Int
    var pixelHeight: Int

    /// Current physical dimensions used by Screen Bean.
    var physicalWidthInches: Double
    var physicalHeightInches: Double

    /// Dimensions reported by macOS when detected.
    var detectedWidthInches: Double
    var detectedHeightInches: Double

    /// True when the physical dimensions have been manually calibrated.
    var isCalibrated: Bool

    /// macOS display position.
    var positionX: Double
    var positionY: Double

    var isPrimary: Bool

    /// Rotation macOS applies to the display: 0, 90, 180 or 270 degrees.
    /// A portrait display is reported as at least 90 even if macOS says 0.
    var rotationDegrees: Int = 0

    /// The display this one mirrors, or 0 when it isn't mirroring.
    var mirrorsDisplayID: CGDirectDisplayID = 0

    /// True when the display is taller than it is wide, as macOS presents it.
    var isPortrait: Bool { pixelHeight > pixelWidth }

    var colorHex: String = DisplayDefaults.colorHex
    /// True once the user has picked this display's color; otherwise it follows the palette.
    var isColorCustom: Bool = false
    var uniformBezel: Bool = true
    /// Bezel thickness on every side when Uniform is on. Kept apart from the four sides below,
    /// so switching Uniform on and off doesn't lose the individual values.
    var bezelUniform: Double = DisplayDefaults.bezelInches
    var bezelTop: Double = DisplayDefaults.bezelInches
    var bezelBottom: Double = DisplayDefaults.bezelInches
    var bezelLeft: Double = DisplayDefaults.bezelInches
    var bezelRight: Double = DisplayDefaults.bezelInches
    var bezelColorHex: String = DisplayDefaults.bezelColorHex
    var showBezel: Bool = true
    /// When locked, the display can't be edited or dragged.
    var isLocked: Bool = false

    /// A planned display that isn't connected. It has no screen to draw on or set a wallpaper for.
    var isVirtual: Bool = false
    /// When on, this display stays in the layout as a stand-in while it is unplugged.
    var keepWhenDisconnected: Bool = false
    /// While on, changing one measurement keeps the shape: the others follow.
    var aspectLocked: Bool = false

    /// True when the size has been changed from what macOS reported.
    var differsFromDetected: Bool {
        abs(physicalWidthInches - detectedWidthInches) > 0.005 || abs(physicalHeightInches - detectedHeightInches) > 0.005
    }
    /// A stand-in for a display that was connected before: virtual on screen, but it keeps that display's identity
    /// and takes over again when the display is plugged back in.
    var isRemembered: Bool { isVirtual && !persistentID.hasPrefix(VirtualDisplayStore.idPrefix) }

    var aspectRatio: Double {
        Double(pixelWidth) / Double(pixelHeight)
    }

    var ppi: Double {
        sqrt(
            Double(pixelWidth * pixelWidth +
                   pixelHeight * pixelHeight)
        ) /
        sqrt(
            physicalWidthInches * physicalWidthInches +
            physicalHeightInches * physicalHeightInches
        )
    }

    // MARK: - Display Detection

    static func detectDisplays() -> [DisplayInfo] {

        var displayCount: UInt32 = 0

        guard CGGetOnlineDisplayList(
            0,
            nil,
            &displayCount
        ) == .success else {
            return []
        }

        var activeDisplays =
            [CGDirectDisplayID](
                repeating: 0,
                count: Int(displayCount)
            )

        guard CGGetOnlineDisplayList(
            displayCount,
            &activeDisplays,
            &displayCount
        ) == .success else {
            return []
        }

        var infos: [DisplayInfo] = []

        for id in activeDisplays {

            let mode =
                CGDisplayCopyDisplayMode(id)

            let modeWidthPx =
                mode?.pixelWidth ??
                Int(CGDisplayPixelsWide(id))

            let modeHeightPx =
                mode?.pixelHeight ??
                Int(CGDisplayPixelsHigh(id))

            let sizeMM =
                CGDisplayScreenSize(id)

            var widthIn =
                Double(sizeMM.width) / 25.4

            var heightIn =
                Double(sizeMM.height) / 25.4

            // CGDisplayBounds is in the rotated, as-seen orientation. Make the pixel
            // and physical sizes match it so a vertical monitor is taller than wide.
            let bounds = CGDisplayBounds(id)
            let portrait = bounds.height > bounds.width
            var widthPx = modeWidthPx
            var heightPx = modeHeightPx
            if widthPx != heightPx, (widthPx > heightPx) == portrait { swap(&widthPx, &heightPx) }
            if widthIn != heightIn, (widthIn > heightIn) == portrait { swap(&widthIn, &heightIn) }

            let reportedRotation = Int(CGDisplayRotation(id))
            let rotationDegrees = portrait && reportedRotation % 180 == 0 ? 90 : reportedRotation

            let origin = bounds.origin

            var info = DisplayInfo(
                displayID: id,
                persistentID: persistentID(
                    for: id
                ),
                nickname: displayName(
                    for: id
                ),
                pixelWidth: widthPx,
                pixelHeight: heightPx,
                physicalWidthInches: widthIn,
                physicalHeightInches: heightIn,
                detectedWidthInches: widthIn,
                detectedHeightInches: heightIn,
                isCalibrated: false,
                positionX: Double(origin.x),
                positionY: Double(origin.y),
                isPrimary: CGDisplayIsMain(id) != 0
            )
            info.rotationDegrees = rotationDegrees
            info.mirrorsDisplayID = CGDisplayMirrorsDisplay(id)

            if let saved = DisplayConfigurationStore.shared.configuration(for: info.persistentID) {
                info.apply(configuration: saved)
                // Saved sizes may predate the display being rotated.
                if info.physicalWidthInches != info.physicalHeightInches,
                   (info.physicalWidthInches > info.physicalHeightInches) != (info.pixelWidth > info.pixelHeight) {
                    swap(&info.physicalWidthInches, &info.physicalHeightInches)
                }
            }
            // Displays without a color of their own take the next palette color.
            if !info.isColorCustom { info.colorHex = DisplayDefaults.paletteColor(at: infos.count) }
            infos.append(info)
        }

        // Virtual displays follow the real ones, which keep the reference position.
        for var virtual in VirtualDisplayStore.shared.displays() {
            if !virtual.isColorCustom { virtual.colorHex = DisplayDefaults.paletteColor(at: infos.count) }
            infos.append(virtual)
        }

        // Displays marked to stay, which aren't plugged in, stand in as virtual ones.
        let connectedIDs = Set(infos.map(\.persistentID))
        let remembered = DisplayConfigurationStore.shared.loadAll().values
            .filter { $0.keepWhenDisconnected && !$0.isVirtual && !connectedIDs.contains($0.persistentID) }
            .sorted { $0.persistentID < $1.persistentID }
        for configuration in remembered {
            var stand = DisplayInfo(virtual: configuration)
            if !stand.isColorCustom { stand.colorHex = DisplayDefaults.paletteColor(at: infos.count) }
            infos.append(stand)
        }

        return infos
    }

    // MARK: - Display Name

    static func displayName(
        for displayID: CGDirectDisplayID
    ) -> String {

        for screen in NSScreen.screens {

            guard let screenNumber =
                screen.deviceDescription[
                    NSDeviceDescriptionKey(
                        "NSScreenNumber"
                    )
                ] as? NSNumber else {
                continue
            }

            if screenNumber.uint32Value ==
                displayID {
                return screen.localizedName
            }
        }

        return "Display \(displayID)"
    }

    // MARK: - Persistent Identity

    static func persistentID(
        for displayID: CGDirectDisplayID
    ) -> String {

        guard let uuid =
            CGDisplayCreateUUIDFromDisplayID(
                displayID
            ) else {
            return "display-\(displayID)"
        }

        return CFUUIDCreateString(
            nil,
            uuid.takeRetainedValue()
        ) as String
    }

    // MARK: - Calibration

    mutating func calibratePhysicalSize(
        width: Double,
        height: Double
    ) {

        guard width > 0,
              height > 0 else {
            return
        }

        physicalWidthInches = width
        physicalHeightInches = height
        isCalibrated = true
    }

    // MARK: - Configuration

    func makeConfiguration()
        -> DisplayConfiguration {

        DisplayConfiguration(
            persistentID: persistentID,
            nickname: nickname,
            widthInches: physicalWidthInches,
            heightInches: physicalHeightInches,
            xInches: 0,
            yInches: 0,
            rotation: 0,
            isCalibrated: isCalibrated,
            colorHex: colorHex,
            isColorCustom: isColorCustom,
            uniformBezel: uniformBezel,
            bezelUniform: bezelUniform,
            bezelTop: bezelTop,
            bezelBottom: bezelBottom,
            bezelLeft: bezelLeft,
            bezelRight: bezelRight,
            bezelColorHex: bezelColorHex,
            showBezel: showBezel,
            isLocked: isLocked,
            isVirtual: isVirtual && !isRemembered,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            keepWhenDisconnected: keepWhenDisconnected,
            aspectLocked: aspectLocked
        )
    }

    mutating func apply(
        configuration: DisplayConfiguration
    ) {

        nickname =
            configuration.nickname

        physicalWidthInches =
            configuration.widthInches

        physicalHeightInches =
            configuration.heightInches

        isCalibrated = configuration.isCalibrated
        colorHex = configuration.colorHex
        isColorCustom = configuration.isColorCustom
        uniformBezel = configuration.uniformBezel
        bezelUniform = configuration.bezelUniform
        bezelTop = configuration.bezelTop
        bezelBottom = configuration.bezelBottom
        bezelLeft = configuration.bezelLeft
        bezelRight = configuration.bezelRight
        bezelColorHex = configuration.bezelColorHex
        showBezel = configuration.showBezel
        isLocked = configuration.isLocked
        keepWhenDisconnected = configuration.keepWhenDisconnected
        aspectLocked = configuration.aspectLocked
    }
}

extension DisplayInfo: Equatable {}

// An initializer here, not in the struct, keeps the memberwise one.
extension DisplayInfo {
    /// A virtual display built from its saved settings.
    init(virtual configuration: DisplayConfiguration) {
        displayID = VirtualDisplayStore.displayID(for: configuration.persistentID)
        persistentID = configuration.persistentID
        nickname = configuration.nickname
        pixelWidth = configuration.pixelWidth
        pixelHeight = configuration.pixelHeight
        physicalWidthInches = configuration.widthInches
        physicalHeightInches = configuration.heightInches
        detectedWidthInches = configuration.widthInches
        detectedHeightInches = configuration.heightInches
        isCalibrated = false
        positionX = 0
        positionY = 0
        isPrimary = false
        isVirtual = true
        apply(configuration: configuration)
    }
}
