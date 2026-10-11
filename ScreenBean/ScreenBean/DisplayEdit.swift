//
//  DisplayEdit.swift
//  ScreenBean
//
//  A set of changes the inspector asks the workspace to apply to the
//  selected display. Only the non-nil fields change.
//

import Cocoa

struct DisplayEdit {
    /// Names the fields being edited, so repeated nudges of one field undo as a single step.
    var undoKey: String {
        [("n", nickname != nil), ("w", width != nil), ("h", height != nil), ("x", x != nil), ("y", y != nil), ("c", color != nil),
         ("u", uniformBezel != nil), ("bu", bezelUniform != nil), ("bt", bezelTop != nil), ("bb", bezelBottom != nil),
         ("bl", bezelLeft != nil), ("br", bezelRight != nil), ("bc", bezelColor != nil), ("sb", showBezel != nil), ("l", isLocked != nil)]
            .filter { $0.1 }.map { $0.0 }.joined(separator: ",")
    }

    var nickname: String?
    var width: Double?
    var height: Double?
    var x: Double?
    var y: Double?
    var color: NSColor?
    var uniformBezel: Bool?
    var bezelUniform: Double?
    var bezelTop: Double?
    var bezelBottom: Double?
    var bezelLeft: Double?
    var bezelRight: Double?
    var bezelColor: NSColor?
    var showBezel: Bool?
    var isLocked: Bool?
}
