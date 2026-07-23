import SwiftUI
import AppKit

/// A resolved color set for one theme variant (light or dark). Hex strings
/// travel as-is to the web layer as CSS custom properties.
struct ThemePalette: Codable, Equatable {
    var bg, bgHi, bgDeep, ink, ink2, ink3, muted, line, lineStrong: String
    var accent, live: String
    var synRed, synAmber, synTeal, synBlue, synPurple, synComment: String
}

enum FontChoice: String, Codable, CaseIterable, Identifiable {
    case fraunces, bricolage, inter, newYork, system, jetbrainsMono, sfMono
    var id: String { rawValue }

    var css: String {
        switch self {
        case .fraunces: "\"Fraunces Variable\", ui-serif, Georgia, serif"
        case .bricolage: "\"Bricolage Grotesque Variable\", ui-rounded, system-ui, sans-serif"
        case .inter: "\"Inter Variable\", system-ui, -apple-system, sans-serif"
        case .newYork: "ui-serif, \"New York\", Georgia, serif"
        case .system: "system-ui, -apple-system, sans-serif"
        case .jetbrainsMono: "\"JetBrains Mono Variable\", ui-monospace, \"SF Mono\", monospace"
        case .sfMono: "ui-monospace, \"SF Mono\", monospace"
        }
    }

    var label: String {
        switch self {
        case .fraunces: "Fraunces"
        case .bricolage: "Bricolage Grotesque"
        case .inter: "Inter"
        case .newYork: "New York (serif)"
        case .system: "System (SF)"
        case .jetbrainsMono: "JetBrains Mono"
        case .sfMono: "SF Mono"
        }
    }
}

struct GalleyTheme: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let light: ThemePalette
    let dark: ThemePalette
    let displayFont: FontChoice
    let bodyFont: FontChoice
    let monoFont: FontChoice
    let headingWeight: Int // 560...760
    let spectral: Bool     // rainbow accents (h1 bar, hr, link hover)
}

/// Per-variant color picks a user has made, layered onto a built-in palette.
struct PaletteOverride: Codable, Equatable {
    var bg, ink, accent: String?
}

/// User overrides layered on a built-in, stored per theme id as JSON in
/// UserDefaults key "galley.themeOverrides.<id>".
struct ThemeOverrides: Codable, Equatable {
    var displayFont, bodyFont, monoFont: FontChoice?
    var headingWeight: Int?
    var spectral: Bool?
    var light: PaletteOverride?
    var dark: PaletteOverride?
}

/// A theme's fields after overrides are applied — what actually gets pushed
/// to the web layer.
struct ResolvedTheme {
    var palette: ThemePalette
    var displayFont: FontChoice
    var bodyFont: FontChoice
    var monoFont: FontChoice
    var headingWeight: Int
    var spectral: Bool
}

enum ThemeStore {
    enum Variant { case light, dark }

    static let builtIns: [GalleyTheme] = [
        GalleyTheme(
            id: "thesis", name: "Thesis",
            blurb: "Warm paper and ink. Galley's own house style.",
            light: ThemePalette(
                bg: "#F1ECE2", bgHi: "#F8F5EE", bgDeep: "#EAE4D6",
                ink: "#15140E", ink2: "#4A4639", ink3: "#403C31", muted: "#8E8879",
                line: "#D9D3C6", lineStrong: "#C3BCAC",
                accent: "#3A6CC9", live: "#1F8A7D",
                synRed: "#C04A5E", synAmber: "#9C6A1F", synTeal: "#177A6E",
                synBlue: "#3A6CC9", synPurple: "#7A51C7", synComment: "#8E8879"
            ),
            dark: ThemePalette(
                bg: "#17160F", bgHi: "#1E1D14", bgDeep: "#121109",
                ink: "#ECE7DA", ink2: "#C9C3B2", ink3: "#B5AF9E", muted: "#8E8879",
                line: "#353327", lineStrong: "#4A473A",
                accent: "#8FBCFF", live: "#36D6C3",
                synRed: "#FF8A9A", synAmber: "#FFC37A", synTeal: "#5DE3D0",
                synBlue: "#8FBCFF", synPurple: "#C9A2FF", synComment: "#7D7869"
            ),
            displayFont: .fraunces, bodyFont: .inter, monoFont: .jetbrainsMono,
            headingWeight: 600, spectral: true
        ),
        GalleyTheme(
            id: "manuscript", name: "Manuscript",
            blurb: "A well-set book. Serif, quiet, no fireworks.",
            light: ThemePalette(
                bg: "#F9F5EC", bgHi: "#FFFDF8", bgDeep: "#F0EADC",
                ink: "#221E17", ink2: "#5A4F41", ink3: "#4A4136", muted: "#93887A",
                line: "#E2DACB", lineStrong: "#CFC5B2",
                accent: "#A33B2E", live: "#4A7A62",
                synRed: "#B0503F", synAmber: "#96702B", synTeal: "#4A7A62",
                synBlue: "#4E6FA3", synPurple: "#7A5E93", synComment: "#93887A"
            ),
            dark: ThemePalette(
                bg: "#201B14", bgHi: "#282219", bgDeep: "#17130D",
                ink: "#EDE4D3", ink2: "#C9BDA6", ink3: "#B4A78F", muted: "#8F8672",
                line: "#3A342A", lineStrong: "#4E463A",
                accent: "#E08D7D", live: "#7FBF9E",
                synRed: "#E08D7D", synAmber: "#D9B36B", synTeal: "#8FCDA9",
                synBlue: "#92AEDC", synPurple: "#B79ED6", synComment: "#8F8672"
            ),
            displayFont: .newYork, bodyFont: .newYork, monoFont: .jetbrainsMono,
            headingWeight: 650, spectral: false
        ),
        GalleyTheme(
            id: "studio", name: "Studio",
            blurb: "Neutral, modern, gets out of the way.",
            light: ThemePalette(
                bg: "#FFFFFF", bgHi: "#F6F7F8", bgDeep: "#EEF0F2",
                ink: "#17181A", ink2: "#45484D", ink3: "#3A3D42", muted: "#8A8F98",
                line: "#E4E6EA", lineStrong: "#CBCFD6",
                accent: "#3B72E8", live: "#12A594",
                synRed: "#D0435B", synAmber: "#B0730C", synTeal: "#0E8A74",
                synBlue: "#2F6BDF", synPurple: "#7A4FD0", synComment: "#8A8F98"
            ),
            dark: ThemePalette(
                bg: "#131417", bgHi: "#1B1D21", bgDeep: "#0D0E10",
                ink: "#E8EAED", ink2: "#B5BAC3", ink3: "#9BA1AB", muted: "#7E838C",
                line: "#2A2D33", lineStrong: "#3D4149",
                accent: "#7AA5FF", live: "#4ADFC4",
                synRed: "#FF7B93", synAmber: "#FFC069", synTeal: "#4ADFC4",
                synBlue: "#82AFFF", synPurple: "#BB9AF7", synComment: "#7E838C"
            ),
            displayFont: .system, bodyFont: .system, monoFont: .sfMono,
            headingWeight: 700, spectral: false
        ),
        GalleyTheme(
            id: "terminal", name: "Terminal",
            blurb: "Everything in mono. For people who live in one.",
            light: ThemePalette(
                bg: "#F4F4F0", bgHi: "#FBFBF8", bgDeep: "#E9E9E2",
                ink: "#1A1D1A", ink2: "#46504A", ink3: "#3B443E", muted: "#7E877F",
                line: "#DBDBD2", lineStrong: "#C2C4B8",
                accent: "#157F5B", live: "#157F5B",
                synRed: "#C25450", synAmber: "#9A7420", synTeal: "#157F5B",
                synBlue: "#3B6FB4", synPurple: "#8455B7", synComment: "#7E877F"
            ),
            dark: ThemePalette(
                bg: "#0D120E", bgHi: "#141B16", bgDeep: "#080C09",
                ink: "#D6E5D8", ink2: "#A3B8A7", ink3: "#8CA391", muted: "#6F8273",
                line: "#243026", lineStrong: "#35453A",
                accent: "#48E5A3", live: "#48E5A3",
                synRed: "#FF7E79", synAmber: "#E5C07B", synTeal: "#56D6AD",
                synBlue: "#61AFEF", synPurple: "#C678DD", synComment: "#6F8273"
            ),
            displayFont: .jetbrainsMono, bodyFont: .jetbrainsMono, monoFont: .jetbrainsMono,
            headingWeight: 700, spectral: false
        ),
        GalleyTheme(
            id: "editorial", name: "Editorial",
            blurb: "High contrast, tight headlines, one red.",
            light: ThemePalette(
                bg: "#FFFEFB", bgHi: "#F7F5F0", bgDeep: "#EFEBE3",
                ink: "#0E0D0B", ink2: "#3E3B36", ink3: "#33302B", muted: "#8C877E",
                line: "#E6E2D9", lineStrong: "#CDC7BA",
                accent: "#E23B2E", live: "#12A594",
                synRed: "#C93A32", synAmber: "#A06B14", synTeal: "#0F8A74",
                synBlue: "#2F62C4", synPurple: "#7648C8", synComment: "#8C877E"
            ),
            dark: ThemePalette(
                bg: "#151412", bgHi: "#1D1C19", bgDeep: "#0E0D0B",
                ink: "#F2EFE9", ink2: "#C6C1B7", ink3: "#B0AA9E", muted: "#8C877E",
                line: "#34322D", lineStrong: "#48453F",
                accent: "#FF6A5C", live: "#4ADFC4",
                synRed: "#FF7B71", synAmber: "#E8B45B", synTeal: "#43D1B4",
                synBlue: "#7FA9F5", synPurple: "#BB97F0", synComment: "#8C877E"
            ),
            displayFont: .bricolage, bodyFont: .inter, monoFont: .jetbrainsMono,
            headingWeight: 760, spectral: false
        ),
    ]

    static func theme(id: String) -> GalleyTheme {
        builtIns.first { $0.id == id } ?? builtIns[0]
    }

    static func current() -> GalleyTheme {
        theme(id: UserDefaults.standard.string(forKey: SettingsKeys.theme) ?? "thesis")
    }

    private static func overridesKey(_ id: String) -> String {
        "galley.themeOverrides.\(id)"
    }

    static func overrides(for id: String) -> ThemeOverrides {
        guard let data = UserDefaults.standard.data(forKey: overridesKey(id)),
              let decoded = try? JSONDecoder().decode(ThemeOverrides.self, from: data)
        else { return ThemeOverrides() }
        return decoded
    }

    /// Storing directly in UserDefaults (rather than @AppStorage) is enough
    /// to trigger it: ReaderModel observes `.didChangeNotification` and
    /// re-pushes options whenever any default changes.
    static func setOverrides(_ overrides: ThemeOverrides, for id: String) {
        let key = overridesKey(id)
        if overrides == ThemeOverrides() {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func resolved(theme: GalleyTheme, variant: Variant) -> ResolvedTheme {
        let overrides = overrides(for: theme.id)
        let base = variant == .light ? theme.light : theme.dark
        let paletteOverride = variant == .light ? overrides.light : overrides.dark
        return ResolvedTheme(
            palette: applying(paletteOverride, to: base),
            displayFont: overrides.displayFont ?? theme.displayFont,
            bodyFont: overrides.bodyFont ?? theme.bodyFont,
            monoFont: overrides.monoFont ?? theme.monoFont,
            headingWeight: overrides.headingWeight ?? theme.headingWeight,
            spectral: overrides.spectral ?? theme.spectral
        )
    }

    /// When the user overrides `bg` or `ink`, derive the dependent tones by
    /// blending toward the other pole so a single color pick still looks
    /// designed instead of flattening every surface to one hex value.
    private static func applying(_ override: PaletteOverride?, to base: ThemePalette) -> ThemePalette {
        guard let override else { return base }
        var p = base
        let bg = override.bg.flatMap(Color.init(hex:)) ?? Color(hex: base.bg)!
        let ink = override.ink.flatMap(Color.init(hex:)) ?? Color(hex: base.ink)!

        if let bgHex = override.bg {
            p.bg = bgHex
            p.bgHi = Color.lerp(bg, ink, 0.035).toHex()
            p.bgDeep = Color.lerp(bg, ink, 0.07).toHex()
            p.line = Color.lerp(bg, ink, 0.12).toHex()
            p.lineStrong = Color.lerp(bg, ink, 0.22).toHex()
        }
        if let inkHex = override.ink {
            p.ink = inkHex
            p.ink2 = Color.lerp(ink, bg, 0.28).toHex()
            p.ink3 = Color.lerp(ink, bg, 0.38).toHex()
        }
        if let accentHex = override.accent {
            p.accent = accentHex
        }
        return p
    }
}

// MARK: - Hex color helpers

extension Color {
    init?(hex: String) {
        guard let ns = NSColor(hex: hex) else { return nil }
        self.init(nsColor: ns)
    }

    func toHex() -> String {
        NSColor(self).toHex()
    }

    static func lerp(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ca = NSColor(a).usingColorSpace(.sRGB) ?? NSColor(a)
        let cb = NSColor(b).usingColorSpace(.sRGB) ?? NSColor(b)
        let r = ca.redComponent + (cb.redComponent - ca.redComponent) * t
        let g = ca.greenComponent + (cb.greenComponent - ca.greenComponent) * t
        let bl = ca.blueComponent + (cb.blueComponent - ca.blueComponent) * t
        return Color(red: r, green: g, blue: bl)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            srgbRed: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255,
            alpha: 1
        )
    }

    func toHex() -> String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
