//
//  VirtualDisplayStore.swift
//  ScreenBean
//
//  Virtual displays are planned displays that aren't connected. Their settings live with
//  the other display configurations; this keeps which ones exist, in order.
//

import Foundation
import CoreGraphics

final class VirtualDisplayStore {
    static let shared = VirtualDisplayStore()
    private let storageKey = "ScreenBean.VirtualDisplayIDs"
    static let idPrefix = "virtual-"

    private init() {}

    /// Persistent IDs of the virtual displays, in the order they were added.
    var ids: [String] {
        get { UserDefaults.standard.stringArray(forKey: storageKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    static func newPersistentID() -> String { idPrefix + UUID().uuidString }

    /// A display ID that never collides with one macOS hands out, and is the same every launch.
    static func displayID(for persistentID: String) -> CGDirectDisplayID {
        var hash: UInt32 = 2166136261
        for byte in persistentID.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return 0xF000_0000 | (hash & 0x0FFF_FFFF)
    }

    /// Display infos for every virtual display that still has saved settings.
    func displays() -> [DisplayInfo] {
        let saved = DisplayConfigurationStore.shared.loadAll()
        return ids.compactMap { id in saved[id].map { DisplayInfo(virtual: $0) } }
    }
}
