//
//  DisplayScaler.swift
//  ScreenBean
//
//  Created by Nathan Pizar on 5/21/25.
//

import Cocoa

class DisplayScaler {
    static let shared = DisplayScaler()
    private init() {}

    var uiScale: CGFloat = 0.1 // Default scale for pixel-based drawing

    func scaleFactor(for info: DisplayInfo) -> CGFloat {
        return uiScale
    }

    func scaleForInches() -> CGFloat {
        return 10.0 // 10 points per inch, adjustable
    }
}
