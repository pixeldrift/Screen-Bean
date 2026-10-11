//
//  ImageLayerStore.swift
//  ScreenBean
//
//  Persists the workspace image layers (reference image, spanned wallpaper)
//  between launches. Image bytes are copied into Application Support so they
//  survive the original file moving; the blend setting lives in UserDefaults.
//

import Cocoa

enum ImageLayerSlot: String, CaseIterable {
    case referenceImage
    case wallpaper
}

/// Where an image layer sits in the workspace, in physical inches.
/// Height follows from the image's aspect ratio.
struct ImageFrame: Codable, Equatable {
    var centerX: Double
    var centerY: Double
    var width: Double
}

final class ImageLayerStore {
    static let shared = ImageLayerStore()
    private let defaults = UserDefaults.standard
    private init() {}

    private func blendKey(_ slot: ImageLayerSlot) -> String { "ScreenBean.ImageLayer.\(slot.rawValue).blend" }

    private func frameKey(_ slot: ImageLayerSlot) -> String { "ScreenBean.ImageLayer.\(slot.rawValue).frame" }

    private func fileURL(_ slot: ImageLayerSlot) -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = support.appendingPathComponent("ScreenBean", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(slot.rawValue)
    }

    func loadImage(_ slot: ImageLayerSlot) -> NSImage? {
        guard let url = fileURL(slot), let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }

    /// Stores the original file's bytes, or removes the stored image when `data` is nil.
    func saveImageData(_ data: Data?, for slot: ImageLayerSlot) {
        guard let url = fileURL(slot) else { return }
        if let data {
            do { try data.write(to: url, options: .atomic) }
            catch { NSLog("ScreenBean: Could not save %@ image: %@", slot.rawValue, error.localizedDescription) }
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func loadFrame(_ slot: ImageLayerSlot) -> ImageFrame? {
        guard let data = defaults.data(forKey: frameKey(slot)) else { return nil }
        return try? JSONDecoder().decode(ImageFrame.self, from: data)
    }

    func saveFrame(_ frame: ImageFrame?, for slot: ImageLayerSlot) {
        if let frame, let data = try? JSONEncoder().encode(frame) { defaults.set(data, forKey: frameKey(slot)) }
        else { defaults.removeObject(forKey: frameKey(slot)) }
    }

    private let clipKey = "ScreenBean.ImageLayer.wallpaper.clipToDisplays"

    func loadWallpaperClip() -> Bool { defaults.bool(forKey: clipKey) }
    func saveWallpaperClip(_ clipped: Bool) { defaults.set(clipped, forKey: clipKey) }

    func loadBlend(_ slot: ImageLayerSlot) -> Double {
        defaults.object(forKey: blendKey(slot)) as? Double ?? 0
    }

    func saveBlend(_ value: Double, for slot: ImageLayerSlot) {
        defaults.set(value, forKey: blendKey(slot))
    }
}
