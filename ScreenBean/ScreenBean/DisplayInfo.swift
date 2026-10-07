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

    /// Legacy display scale value.
    var scaleFactor: CGFloat

    /// macOS display position.
    var positionX: Double
    var positionY: Double

    var isPrimary: Bool

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

            let widthPx =
                mode?.pixelWidth ??
                Int(CGDisplayPixelsWide(id))

            let heightPx =
                mode?.pixelHeight ??
                Int(CGDisplayPixelsHigh(id))

            let sizeMM =
                CGDisplayScreenSize(id)

            let widthIn =
                Double(sizeMM.width) / 25.4

            let heightIn =
                Double(sizeMM.height) / 25.4

            let origin =
                CGDisplayBounds(id).origin

            let info = DisplayInfo(
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
                scaleFactor: 0.1,
                positionX: Double(origin.x),
                positionY: Double(origin.y),
                isPrimary: CGDisplayIsMain(id) != 0
            )

            infos.append(info)
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
            isCalibrated: isCalibrated
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

        isCalibrated =
            configuration.isCalibrated
    }

    // MARK: - Layout Helper

    struct DisplayLayoutHelper {

        static func normalizedDisplays(
            from displays: [DisplayInfo],
            fitting size: CGSize,
            padding: CGFloat = 40
        ) -> [
            (
                info: DisplayInfo,
                frame: CGRect
            )
        ] {

            guard !displays.isEmpty else {
                return []
            }

            let minX =
                displays.map {
                    $0.positionX
                }.min() ?? 0

            let minY =
                displays.map {
                    $0.positionY
                }.min() ?? 0

            let maxX =
                displays.map {
                    $0.positionX +
                    $0.physicalWidthInches
                }.max() ?? 1

            let maxY =
                displays.map {
                    $0.positionY +
                    $0.physicalHeightInches
                }.max() ?? 1

            let layoutWidth =
                maxX - minX

            let layoutHeight =
                maxY - minY

            let scaleX =
                (size.width - padding * 2) /
                layoutWidth

            let scaleY =
                (size.height - padding * 2) /
                layoutHeight

            let scale =
                min(scaleX, scaleY)

            return displays.map { display in

                let width =
                    CGFloat(
                        display.physicalWidthInches
                    ) * scale

                let height =
                    CGFloat(
                        display.physicalHeightInches
                    ) * scale

                let x =
                    CGFloat(
                        display.positionX - minX
                    ) * scale + padding

                let y =
                    CGFloat(
                        display.positionY - minY
                    ) * scale + padding

                return (
                    info: display,
                    frame: CGRect(
                        x: x,
                        y: y,
                        width: width,
                        height: height
                    )
                )
            }
        }
    }
}
