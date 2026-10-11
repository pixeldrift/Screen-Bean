//
//  UndoCenter.swift
//  ScreenBean
//
//  Undo and redo for layout edits. Each edit records a snapshot of what undo covers
//  (displays, guides, image placement), and undoing swaps back to it.
//

import Foundation

/// An image layer's placement, as far as undo is concerned.
struct ImageLayerState: Equatable {
    var frame: ImageFrame?
    var isLocked: Bool
}

/// Everything undo and redo restore.
struct WorkspaceSnapshot: Equatable {
    var displays: [DisplayInfo]
    var layout: [PhysicalLayout.Display]
    var guides: [Guide]
    var reference: ImageLayerState
    var wallpaper: ImageLayerState
}

final class UndoCenter {
    static let shared = UndoCenter()

    let manager = UndoManager()

    /// Set by the workspace: reads and writes the state undo covers.
    var capture: (() -> WorkspaceSnapshot?)?
    var restore: ((WorkspaceSnapshot) -> Void)?

    private var lastCoalesceKey: String?
    private var lastCoalesceTime = Date.distantPast

    private init() {
        manager.levelsOfUndo = 200
    }

    /// Records an undo step if the state differs from `before`. Steps with the same
    /// `coalesceKey` made within a second of each other (a scrub, a nudge) share one step.
    func record(_ name: String, before: WorkspaceSnapshot, coalesceKey: String? = nil) {
        guard let capture, let now = capture(), now != before else { return }
        let now = Date()
        if let key = coalesceKey, key == lastCoalesceKey, now.timeIntervalSince(lastCoalesceTime) < 1, manager.canUndo {
            lastCoalesceTime = now
            return
        }
        lastCoalesceKey = coalesceKey
        lastCoalesceTime = now
        register(name, restoring: before)
    }

    /// Runs `change` and records it as one undo step.
    func perform(_ name: String, coalesceKey: String? = nil, _ change: () -> Void) {
        guard let capture, let before = capture() else { change(); return }
        change()
        record(name, before: before, coalesceKey: coalesceKey)
    }

    func undo() {
        lastCoalesceKey = nil
        manager.undo()
    }

    func redo() {
        lastCoalesceKey = nil
        manager.redo()
    }

    /// Registers a step that puts `snapshot` back. While it runs it registers the reverse step, which is how redo works.
    private func register(_ name: String, restoring snapshot: WorkspaceSnapshot) {
        manager.registerUndo(withTarget: self) { center in
            let current = center.capture?()
            center.restore?(snapshot)
            if let current { center.register(name, restoring: current) }
        }
        manager.setActionName(name)
    }
}
