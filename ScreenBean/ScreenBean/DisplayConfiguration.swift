//
//  DisplayConfiguration.swift
//  ScreenBean
//
//  Created by Nathan Pizar on 10/7/26.
//

import Foundation

struct DisplayConfiguration: Codable {
    var persistentID: String
    var nickname: String
    var widthInches: Double
    var heightInches: Double
    var xInches: Double
    var yInches: Double
    var rotation: Double
    var isCalibrated: Bool

    // Inspector appearance and bezel settings. Defaults keep older
    // saved configurations readable when these keys are absent.
    var colorHex: String
    var isColorCustom: Bool
    var uniformBezel: Bool
    var bezelUniform: Double
    var bezelTop: Double
    var bezelBottom: Double
    var bezelLeft: Double
    var bezelRight: Double
    var bezelColorHex: String
    var showBezel: Bool
    var isLocked: Bool

    /// A planned display that isn't connected. Its pixel size is kept here, since there's no
    /// hardware to read it from.
    var isVirtual: Bool
    var pixelWidth: Int
    var pixelHeight: Int
    /// A connected display kept in the layout, as a virtual stand-in, while it is unplugged.
    var keepWhenDisconnected: Bool
    /// While on, changing one measurement keeps the shape: the others follow.
    var aspectLocked: Bool

    init(
        persistentID: String,
        nickname: String,
        widthInches: Double,
        heightInches: Double,
        xInches: Double,
        yInches: Double,
        rotation: Double,
        isCalibrated: Bool,
        colorHex: String = DisplayDefaults.colorHex,
        isColorCustom: Bool = false,
        uniformBezel: Bool = true,
        bezelUniform: Double = DisplayDefaults.bezelInches,
        bezelTop: Double = DisplayDefaults.bezelInches,
        bezelBottom: Double = DisplayDefaults.bezelInches,
        bezelLeft: Double = DisplayDefaults.bezelInches,
        bezelRight: Double = DisplayDefaults.bezelInches,
        bezelColorHex: String = DisplayDefaults.bezelColorHex,
        showBezel: Bool = true,
        isLocked: Bool = false,
        isVirtual: Bool = false,
        pixelWidth: Int = 1920,
        pixelHeight: Int = 1080,
        keepWhenDisconnected: Bool = false,
        aspectLocked: Bool = false
    ) {
        self.persistentID = persistentID
        self.nickname = nickname
        self.widthInches = widthInches
        self.heightInches = heightInches
        self.xInches = xInches
        self.yInches = yInches
        self.rotation = rotation
        self.isCalibrated = isCalibrated
        self.colorHex = colorHex
        self.isColorCustom = isColorCustom
        self.uniformBezel = uniformBezel
        self.bezelUniform = bezelUniform
        self.bezelTop = bezelTop
        self.bezelBottom = bezelBottom
        self.bezelLeft = bezelLeft
        self.bezelRight = bezelRight
        self.bezelColorHex = bezelColorHex
        self.showBezel = showBezel
        self.isLocked = isLocked
        self.isVirtual = isVirtual
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.keepWhenDisconnected = keepWhenDisconnected
        self.aspectLocked = aspectLocked
    }

    private enum CodingKeys: String, CodingKey {
        case persistentID, nickname, widthInches, heightInches
        case xInches, yInches, rotation, isCalibrated
        case colorHex, isColorCustom, uniformBezel, bezelUniform, bezelTop, bezelBottom, bezelLeft, bezelRight
        case bezelColorHex, showBezel, isLocked, isVirtual, pixelWidth, pixelHeight, keepWhenDisconnected, aspectLocked
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        persistentID = try values.decode(String.self, forKey: .persistentID)
        nickname = try values.decodeIfPresent(String.self, forKey: .nickname) ?? "Display"
        widthInches = try values.decodeIfPresent(Double.self, forKey: .widthInches) ?? 23.6
        heightInches = try values.decodeIfPresent(Double.self, forKey: .heightInches) ?? 13.4
        xInches = try values.decodeIfPresent(Double.self, forKey: .xInches) ?? 0
        yInches = try values.decodeIfPresent(Double.self, forKey: .yInches) ?? 0
        rotation = try values.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        isCalibrated = try values.decodeIfPresent(Bool.self, forKey: .isCalibrated) ?? false
        colorHex = try values.decodeIfPresent(String.self, forKey: .colorHex) ?? DisplayDefaults.colorHex
        // Settings saved before the palette existed count as custom only if they changed the color.
        isColorCustom = try values.decodeIfPresent(Bool.self, forKey: .isColorCustom) ?? (colorHex != DisplayDefaults.legacyColorHex)
        uniformBezel = try values.decodeIfPresent(Bool.self, forKey: .uniformBezel) ?? true
        bezelTop = try values.decodeIfPresent(Double.self, forKey: .bezelTop) ?? DisplayDefaults.bezelInches
        // Earlier versions used the top value for a uniform bezel.
        bezelUniform = try values.decodeIfPresent(Double.self, forKey: .bezelUniform) ?? bezelTop
        bezelBottom = try values.decodeIfPresent(Double.self, forKey: .bezelBottom) ?? DisplayDefaults.bezelInches
        bezelLeft = try values.decodeIfPresent(Double.self, forKey: .bezelLeft) ?? DisplayDefaults.bezelInches
        bezelRight = try values.decodeIfPresent(Double.self, forKey: .bezelRight) ?? DisplayDefaults.bezelInches
        bezelColorHex = try values.decodeIfPresent(String.self, forKey: .bezelColorHex) ?? DisplayDefaults.bezelColorHex
        showBezel = try values.decodeIfPresent(Bool.self, forKey: .showBezel) ?? true
        isLocked = try values.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        isVirtual = try values.decodeIfPresent(Bool.self, forKey: .isVirtual) ?? false
        pixelWidth = try values.decodeIfPresent(Int.self, forKey: .pixelWidth) ?? 1920
        pixelHeight = try values.decodeIfPresent(Int.self, forKey: .pixelHeight) ?? 1080
        keepWhenDisconnected = try values.decodeIfPresent(Bool.self, forKey: .keepWhenDisconnected) ?? false
        aspectLocked = try values.decodeIfPresent(Bool.self, forKey: .aspectLocked) ?? false
    }
}
