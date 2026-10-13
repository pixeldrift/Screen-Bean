//
//  Guides.swift
//  ScreenBean
//
//  Alignment guides: lines across the shared physical canvas. Edge guides continue
//  each display's edges out in both directions, like infinite crop marks; custom
//  guides are dragged out from the rulers. Positions are in physical inches.
//

import Cocoa

enum GuideAxis: String, Codable {
    /// A line of constant y.
    case horizontal
    /// A line of constant x.
    case vertical
}

/// A guide the user created.
struct Guide: Codable, Equatable {
    var id = UUID()
    var axis: GuideAxis
    /// y for a horizontal guide, x for a vertical one.
    var position: Double
}

/// A guide ready to draw, whether it is a custom one or derived from a display edge.
struct ResolvedGuide {
    let axis: GuideAxis
    let position: Double
    let color: NSColor
    /// The id of the custom guide, or nil for an edge guide.
    let customID: UUID?

    var isCustom: Bool { customID != nil }
}

enum EdgeGuideScope: Int {
    case allDisplays
    case selectedDisplay
}

/// Which guides are shown. Each change posts `didChange`.
enum GuideSettings {
    static let didChange = Notification.Name("ScreenBean.GuideSettingsDidChange")

    private static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    private static func set(_ value: Any, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Guides continuing the displays' edges, in the workspace and on the real screens.
    static var showEdgeGuides: Bool {
        get { bool("ScreenBean.ShowEdgeGuides", default: true) }
        set { set(newValue, forKey: "ScreenBean.ShowEdgeGuides") }
    }

    /// The rulers along the top and left of the workspace.
    static var showRulers: Bool {
        get { bool("ScreenBean.ShowRulers", default: true) }
        set { set(newValue, forKey: "ScreenBean.ShowRulers") }
    }

    /// Where the mouse can cross between displays: linked edges, drawn as translucent shapes in the gaps.
    static var showMouseTransit: Bool {
        get { bool("ScreenBean.ShowMouseTransit", default: false) }
        set { set(newValue, forKey: "ScreenBean.ShowMouseTransit") }
    }

    /// Draw the transit zones on the real screens too: each covered stretch of a screen's edge in the color of the display it connects to.
    static var showTransitOnScreens: Bool {
        get { bool("ScreenBean.ShowTransitOnScreens", default: false) }
        set { set(newValue, forKey: "ScreenBean.ShowTransitOnScreens") }
    }

    /// The guides dragged out of the rulers.
    static var showCustomGuides: Bool {
        get { bool("ScreenBean.ShowCustomGuides", default: true) }
        set { set(newValue, forKey: "ScreenBean.ShowCustomGuides") }
    }

    /// Which displays contribute edge guides.
    static var edgeScope: EdgeGuideScope {
        get { EdgeGuideScope(rawValue: UserDefaults.standard.integer(forKey: "ScreenBean.EdgeGuideScope")) ?? .allDisplays }
        set { set(newValue.rawValue, forKey: "ScreenBean.EdgeGuideScope") }
    }

    /// Dragged edges snap to guides.
    static var snapToGuides: Bool {
        get { bool("ScreenBean.SnapToGuides", default: true) }
        set { set(newValue, forKey: "ScreenBean.SnapToGuides") }
    }

    /// Dragged displays snap bezel to bezel against their neighbors.
    static var snapToBezels: Bool {
        get { bool("ScreenBean.SnapToBezels", default: true) }
        set { set(newValue, forKey: "ScreenBean.SnapToBezels") }
    }

    /// Measurements across the gaps between displays.
    static var showGapMeasurements: Bool {
        get { bool("ScreenBean.ShowGapMeasurements", default: true) }
        set { set(newValue, forKey: "ScreenBean.ShowGapMeasurements") }
    }

}

/// The user's custom guides, saved between launches.
final class GuideStore {
    static let shared = GuideStore()
    static let didChange = Notification.Name("ScreenBean.GuidesDidChange")

    private let key = "ScreenBean.CustomGuides"
    private(set) var guides: [Guide] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode([Guide].self, from: data) {
            guides = saved
        }
    }

    func guide(withID id: UUID) -> Guide? { guides.first { $0.id == id } }

    func add(_ guide: Guide) {
        guides.append(guide)
        changed()
    }

    /// Moves a guide. Call `save()` when the move is finished.
    func setPosition(_ position: Double, for id: UUID) {
        guard let index = guides.firstIndex(where: { $0.id == id }) else { return }
        guides[index].position = position
        changed()
    }

    /// Puts a whole set of guides back, as undo does.
    func replaceAll(_ newGuides: [Guide]) {
        guides = newGuides
        save()
        changed()
    }

    func remove(_ id: UUID) {
        guides.removeAll { $0.id == id }
        save()
        changed()
    }

    func removeAll() {
        guides.removeAll()
        save()
        changed()
    }

    func save() {
        if let data = try? JSONEncoder().encode(guides) { UserDefaults.standard.set(data, forKey: key) }
    }

    private func changed() { NotificationCenter.default.post(name: Self.didChange, object: nil) }
}
