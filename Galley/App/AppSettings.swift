import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum Measure: Int, CaseIterable, Identifiable {
    case narrow = 62
    case normal = 70
    case wide = 84
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .narrow: "Narrow"
        case .normal: "Normal"
        case .wide: "Wide"
        }
    }
}

enum FrontMatterDisplay: String, CaseIterable, Identifiable {
    case card, hidden
    var id: String { rawValue }
    var label: String {
        switch self {
        case .card: "Metadata card"
        case .hidden: "Hidden"
        }
    }
}

/// App-wide reading defaults. Per-window zoom layers on top of `textScale`.
enum SettingsKeys {
    static let theme = "galley.theme"
    static let mode = "galley.mode"
    static let textScale = "galley.textScale"
    static let measure = "galley.measure"
    static let liveReload = "galley.liveReload"
    static let followTail = "galley.followTail"
    static let restoreScroll = "galley.restoreScroll"
    static let smartTypography = "galley.smartTypography"
    static let frontMatter = "galley.frontMatter"
    static let allowRemote = "galley.allowRemoteImages"
}

extension UserDefaults {
    static func registerGalleyDefaults() {
        migrateLegacyAppearance()
        UserDefaults.standard.register(defaults: [
            SettingsKeys.theme: "thesis",
            SettingsKeys.mode: AppearanceMode.system.rawValue,
            SettingsKeys.textScale: 1.0,
            SettingsKeys.measure: Measure.normal.rawValue,
            SettingsKeys.liveReload: true,
            SettingsKeys.followTail: true,
            SettingsKeys.restoreScroll: true,
            SettingsKeys.smartTypography: true,
            SettingsKeys.frontMatter: FrontMatterDisplay.card.rawValue,
            SettingsKeys.allowRemote: true,
        ])
    }

    /// One-shot migration from the old "galley.appearance" (system/paper/ink)
    /// setting to "galley.mode" (system/light/dark). Silent — runs once,
    /// since the old key is removed afterward.
    private static func migrateLegacyAppearance() {
        let d = UserDefaults.standard
        guard let old = d.string(forKey: "galley.appearance") else { return }
        switch old {
        case "paper": d.set(AppearanceMode.light.rawValue, forKey: SettingsKeys.mode)
        case "ink": d.set(AppearanceMode.dark.rawValue, forKey: SettingsKeys.mode)
        default: break // "system" needs no translation
        }
        d.removeObject(forKey: "galley.appearance")
    }
}
