//
//  GapMeasurement.swift
//  ScreenBean
//
//  A measurement across the empty space between two displays, with where along the
//  gap it is drawn. Positions are physical inches.
//

import Cocoa

struct GapMeasurement {
    /// Which way the measurement arrow points.
    enum Direction {
        /// Between a left and a right display; the arrow runs along x.
        case horizontal
        /// Between a lower and an upper display; the arrow runs along y.
        case vertical
    }

    let direction: Direction
    /// The display on the low side (left, or lower) and the high side (right, or upper).
    let first: CGDirectDisplayID
    let second: CGDirectDisplayID
    /// Distance between the two edges.
    let gap: CGFloat
    /// The arrow's ends, on the first display's edge and the second's.
    let start: CGPoint
    let end: CGPoint
    /// The span along the edges where both displays face each other, and where in it the arrow sits.
    let overlapLow: CGFloat
    let overlapHigh: CGFloat
    let placement: Double
    /// Identifies the pair, so its placement can be remembered.
    let key: String
}

/// Where along each gap the user has slid its measurement, from 0 to 1, saved between launches.
enum GapPlacementStore {
    private static let storageKey = "ScreenBean.GapMeasurementPlacements"

    private static var all: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    static func placement(for key: String) -> Double { all[key] ?? 0.5 }

    static func setPlacement(_ value: Double, for key: String) {
        var current = all
        current[key] = min(max(value, 0), 1)
        all = current
    }
}
