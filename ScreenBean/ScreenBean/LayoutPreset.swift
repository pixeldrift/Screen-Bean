//
//  LayoutPreset.swift
//  ScreenBean
//
//  A named, saved layout: where every display sits and how it looks, plus the guides and
//  image placement. Lets one laptop switch between, say, a work desk and a home desk.
//

import Foundation

struct LayoutPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var displays: [DisplayConfiguration]
    var guides: [Guide]
    var referenceFrame: ImageFrame?
    var wallpaperFrame: ImageFrame?
    var referenceLocked: Bool
    var wallpaperLocked: Bool
    /// Persistent IDs of the connected displays when this was saved, used to suggest the matching preset.
    var connectedIDs: [String]
}

final class LayoutPresetStore {
    static let shared = LayoutPresetStore()
    static let didChange = Notification.Name("ScreenBean.LayoutPresetsDidChange")
    private let presetsKey = "ScreenBean.LayoutPresets"
    private let activeKey = "ScreenBean.ActiveLayoutPreset"
    private let suggestedKey = "ScreenBean.LastSuggestedDisplaySet"

    private init() {}

    private(set) var presets: [LayoutPreset] {
        get {
            guard let data = UserDefaults.standard.data(forKey: presetsKey) else { return [] }
            do { return try JSONDecoder().decode([LayoutPreset].self, from: data) }
            catch { NSLog("ScreenBean: Could not load layout presets: %@", error.localizedDescription); return [] }
        }
        set {
            do { UserDefaults.standard.set(try JSONEncoder().encode(newValue), forKey: presetsKey) }
            catch { NSLog("ScreenBean: Could not save layout presets: %@", error.localizedDescription) }
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// The preset last saved or applied, which "Update" overwrites.
    var activeID: UUID? {
        get { UserDefaults.standard.string(forKey: activeKey).flatMap(UUID.init(uuidString:)) }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: activeKey)
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    var active: LayoutPreset? { activeID.flatMap(preset(withID:)) }

    func preset(withID id: UUID) -> LayoutPreset? { presets.first { $0.id == id } }

    func add(_ preset: LayoutPreset) {
        presets.append(preset)
        activeID = preset.id
    }

    /// Replaces a preset's contents, keeping its name.
    func update(_ id: UUID, with contents: LayoutPreset) {
        var all = presets
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        var replacement = contents
        replacement.id = id
        replacement.name = all[i].name
        all[i] = replacement
        presets = all
    }

    func rename(_ id: UUID, to name: String) {
        var all = presets
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].name = name
        presets = all
    }

    func delete(_ id: UUID) {
        presets = presets.filter { $0.id != id }
        if activeID == id { activeID = nil }
    }

    /// Presets saved with exactly this set of connected displays.
    func presets(matching connected: Set<String>) -> [LayoutPreset] {
        guard !connected.isEmpty else { return [] }
        return presets.filter { Set($0.connectedIDs) == connected }
    }

    /// The display set last offered a preset for, so the same set isn't offered again and again.
    var lastSuggestedSet: String? {
        get { UserDefaults.standard.string(forKey: suggestedKey) }
        set { UserDefaults.standard.set(newValue, forKey: suggestedKey) }
    }
}
