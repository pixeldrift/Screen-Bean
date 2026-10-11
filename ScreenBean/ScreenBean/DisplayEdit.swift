//
//  DisplayEdit.swift
//  ScreenBean
//
//  A set of changes the inspector asks the workspace to apply to the
//  selected display. Only the non-nil fields change.
//

import Cocoa

struct DisplayEdit {
    var nickname: String?
    var width: Double?
    var height: Double?
    var x: Double?
    var y: Double?
    var color: NSColor?
    var uniformBezel: Bool?
    var bezelTop: Double?
    var bezelBottom: Double?
    var bezelLeft: Double?
    var bezelRight: Double?
    var showBezel: Bool?
    var isLocked: Bool?
}
