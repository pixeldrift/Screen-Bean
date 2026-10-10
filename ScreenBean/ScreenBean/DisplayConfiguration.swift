//
//  DisplayConfiguration.swift
//  ScreenBean
//
//  Created by Nathan Pizar on 10/7/26.
//

import Foundation

struct DisplayConfiguration: Codable {
    let persistentID: String
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
    var uniformBezel: Bool
    var bezelTop: Double
    var bezelBottom: Double
    var bezelLeft: Double
    var bezelRight: Double

    init(
        persistentID: String,
        nickname: String,
        widthInches: Double,
        heightInches: Double,
        xInches: Double,
        yInches: Double,
        rotation: Double,
        isCalibrated: Bool,
        colorHex: String = "28B7B0",
        uniformBezel: Bool = true,
        bezelTop: Double = 0.25,
        bezelBottom: Double = 0.25,
        bezelLeft: Double = 0.25,
        bezelRight: Double = 0.25
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
        self.uniformBezel = uniformBezel
        self.bezelTop = bezelTop
        self.bezelBottom = bezelBottom
        self.bezelLeft = bezelLeft
        self.bezelRight = bezelRight
    }

    private enum CodingKeys: String, CodingKey {
        case persistentID, nickname, widthInches, heightInches
        case xInches, yInches, rotation, isCalibrated
        case colorHex, uniformBezel, bezelTop, bezelBottom, bezelLeft, bezelRight
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
        colorHex = try values.decodeIfPresent(String.self, forKey: .colorHex) ?? "28B7B0"
        uniformBezel = try values.decodeIfPresent(Bool.self, forKey: .uniformBezel) ?? true
        bezelTop = try values.decodeIfPresent(Double.self, forKey: .bezelTop) ?? 0.25
        bezelBottom = try values.decodeIfPresent(Double.self, forKey: .bezelBottom) ?? 0.25
        bezelLeft = try values.decodeIfPresent(Double.self, forKey: .bezelLeft) ?? 0.25
        bezelRight = try values.decodeIfPresent(Double.self, forKey: .bezelRight) ?? 0.25
    }
}
