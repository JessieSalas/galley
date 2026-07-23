import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case system, paper, ink
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "System"
        case .paper: "Paper"
        case .ink: "Ink"
        }
    }
}

enum Typeface: String, CaseIterable, Identifiable {
    case standard = "default"
    case serif
    case mono
    case system
    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: "Galley"
        case .serif: "Serif"
        case .mono: "Mono"
        case .system: "System"
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
    static let appearance = "galley.appearance"
    static let typeface = "galley.typeface"
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
        UserDefaults.standard.register(defaults: [
            SettingsKeys.appearance: Appearance.system.rawValue,
            SettingsKeys.typeface: Typeface.standard.rawValue,
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
}
