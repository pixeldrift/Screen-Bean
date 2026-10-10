//
//  DisplayConfigurationStore.swift
//  ScreenBean
//
//  Stores per-monitor settings by persistent display identity.
//

import Foundation

final class DisplayConfigurationStore {
    static let shared = DisplayConfigurationStore()
    private let storageKey = "ScreenBean.DisplayConfigurations"
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadAll() -> [String: DisplayConfiguration] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        do {
            return try JSONDecoder().decode([String: DisplayConfiguration].self, from: data)
        } catch {
            NSLog("ScreenBean: Could not load display configurations: %@", error.localizedDescription)
            return [:]
        }
    }

    func configuration(for persistentID: String) -> DisplayConfiguration? {
        loadAll()[persistentID]
    }

    func save(_ configuration: DisplayConfiguration) {
        var all = loadAll()
        all[configuration.persistentID] = configuration
        do {
            defaults.set(try JSONEncoder().encode(all), forKey: storageKey)
        } catch {
            NSLog("ScreenBean: Could not save display configuration: %@", error.localizedDescription)
        }
    }

    func save(_ configurations: [DisplayConfiguration]) {
        var all = loadAll()
        for configuration in configurations {
            all[configuration.persistentID] = configuration
        }
        do {
            defaults.set(try JSONEncoder().encode(all), forKey: storageKey)
        } catch {
            NSLog("ScreenBean: Could not save display configurations: %@", error.localizedDescription)
        }
    }
}
