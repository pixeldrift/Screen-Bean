//
//  AppSettings.swift
//  ScreenBean
//
//  App-wide display settings that override or sit above per-display ones.
//

import Foundation

/// A global switch over every display's own "Show bezel" setting.
enum BezelVisibility: Int {
    /// Each display uses its own setting.
    case perDisplay
    case showAll
    case hideAll

    /// Posted when `current` changes, so the workspace and inspector can redraw.
    static let didChange = Notification.Name("ScreenBean.BezelVisibilityDidChange")

    private static let key = "ScreenBean.BezelVisibility"

    static var current: BezelVisibility {
        get { BezelVisibility(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .perDisplay }
        set {
            guard newValue != current else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Whether a display's bezel is shown, given its own setting and the global override.
    static func isShown(displaySetting: Bool) -> Bool {
        switch current {
        case .perDisplay: return displaySetting
        case .showAll: return true
        case .hideAll: return false
        }
    }
}
