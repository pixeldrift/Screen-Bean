//
//  DisplayConfiguration.swift
//  ScreenBean
//
//  Created by Nathan Pizar on 10/7/26.
//
import Foundation
struct DisplayConfiguration: Codable {
    /// Apple's persistent UUID for the physical display.
    let persistentID: String
    /// Screen Bean's user-defined display name.
    var nickname: String
    /// Physical dimensions in inches.
    var widthInches: Double
    var heightInches: Double
    /// Position in Screen Bean's physical workspace.
    var xInches: Double
    var yInches: Double
    /// Display rotation in degrees.
    var rotation: Double
    /// Whether the physical dimensions have been
    /// manually calibrated by the user.
    var isCalibrated: Bool
}
