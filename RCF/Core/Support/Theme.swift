import SwiftUI

/// App theme — palette per selection, persisted in UserDefaults.
/// Ink Dark (warm ink canvas, rust accent) is the default identity.
enum ThemePreference: String, CaseIterable, Identifiable, Codable {
    case light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var palette: Palette {
        switch self {
        case .light: .light
        case .dark: .inkDark
        }
    }

    var isLight: Bool { self == .light }

    /// Resolved SwiftUI color scheme (Ink Dark renders as dark).
    var colorScheme: ColorScheme { isLight ? .light : .dark }
}

/// Central theme manager: active palette + persistence. The root view observes
/// this; `.cf*` tokens read `active` so a switch invalidates the whole tree.
@MainActor
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    static let preferenceKey = "rcf.theme.preference"
    /// Legacy values: pre-2.0 "system", and 2.0's "inkDark" (now renamed Dark).
    private static let legacyRemap: [String: String] = ["system": "dark", "inkDark": "dark"]

    private let defaults: UserDefaults

    /// Current preference. Persisted on change; mirrors to `ActivePalette`
    /// for nonisolated token reads.
    var preference: ThemePreference {
        didSet {
            defaults.set(preference.rawValue, forKey: Self.preferenceKey)
            ActivePalette.current = preference.palette
        }
    }

    /// Palette for the current preference — the single source views read.
    var palette: Palette { preference.palette }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.preferenceKey)
        let raw = stored.flatMap { Self.legacyRemap[$0] } ?? stored ?? ThemePreference.dark.rawValue
        preference = ThemePreference(rawValue: raw) ?? .dark
        ActivePalette.current = preference.palette
    }
}

/// Snapshot of the active palette, readable from any isolation (incl. the
/// nonisolated `.cf*` tokens). Written only by ThemeManager on the main actor;
/// views re-render via the root's observation of the manager.
nonisolated enum ActivePalette: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _current: Palette = .inkDark
    static var current: Palette {
        get { lock.lock(); defer { lock.unlock() }; return _current }
        set { lock.lock(); defer { lock.unlock() }; _current = newValue }
    }
}

/// Semantic tokens backed by the active palette. Names unchanged from 1.x so
/// every existing view themes for free; switching preference re-renders all.
nonisolated extension ShapeStyle where Self == Color {
    static var cfAccent: Color { ActivePalette.current.accent }
    static var cfBackground: Color { ActivePalette.current.canvas }
    static var cfFooter: Color { ActivePalette.current.footer }
    static var cfSurface: Color { ActivePalette.current.panel }
    static var cfSurfaceSecondary: Color { ActivePalette.current.panelRaised }
    static var cfText: Color { ActivePalette.current.ink }
    static var cfTextSecondary: Color { ActivePalette.current.inkSecondary }
    static var cfTextTertiary: Color { ActivePalette.current.inkTertiary }
    static var cfBorder: Color { ActivePalette.current.separator }
    static var cfSuccess: Color { ActivePalette.current.success }
    static var cfWarning: Color { ActivePalette.current.warning }
    static var cfDanger: Color { ActivePalette.current.danger }
    static var cfInfo: Color { ActivePalette.current.info }
    static var cfBadge: Color { ActivePalette.current.badge }
    static var cfBadgeText: Color { ActivePalette.current.badgeInk }
}
