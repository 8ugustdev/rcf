import SwiftUI

/// A complete color palette for one theme — every surface the app draws.
/// Values adapted from rmote's ThemePalette; tokens map onto the existing
/// `.cf*` extension so all views theme without per-file changes.
nonisolated struct Palette: Sendable, Equatable {
    let canvas: Color        // app background
    let ink: Color           // primary text
    let inkSecondary: Color  // secondary text / metadata
    let inkTertiary: Color   // hints, placeholders
    let accent: Color        // interactive elements
    let accentSoft: Color    // accent at low alpha (selections, chips)
    let panel: Color         // cards, list rows
    let panelRaised: Color   // elevated cards, popovers
    let footer: Color        // nav/toolbar chrome
    let separator: Color     // hairline strokes
    let selection: Color     // list selection / focus ring
    let success: Color
    let warning: Color
    let danger: Color
    let info: Color
    let badge: Color
    let badgeInk: Color
    let terminalBg: Color    // workers tail / code surfaces
    let terminalInk: Color
}

nonisolated extension Palette {
    /// Ink Dark — warm ink canvas, cream text, rust accent (rmote DNA). Default.
    static let inkDark = Palette(
        canvas: Color(red: 0.098, green: 0.090, blue: 0.071),        // #191712
        ink: Color(red: 0.804, green: 0.776, blue: 0.722),           // #CDC6B8
        inkSecondary: Color(red: 0.580, green: 0.545, blue: 0.471),  // #948B78
        inkTertiary: Color(red: 0.42, green: 0.39, blue: 0.33),
        accent: Color(red: 0.851, green: 0.482, blue: 0.247),        // #D97B3F
        accentSoft: Color(red: 0.851, green: 0.482, blue: 0.247, opacity: 0.22),
        panel: Color(red: 0.129, green: 0.118, blue: 0.090),         // #211E17
        panelRaised: Color(red: 0.161, green: 0.149, blue: 0.114),   // #29261D
        footer: Color(red: 0.078, green: 0.067, blue: 0.051),        // #14110D
        separator: Color(red: 0.227, green: 0.208, blue: 0.165),     // #3A352A
        selection: Color(red: 0.851, green: 0.482, blue: 0.247, opacity: 0.45),
        success: Color(red: 0.525, green: 0.710, blue: 0.416),       // #86B56A
        warning: Color(red: 0.898, green: 0.714, blue: 0.353),       // #E5B65A
        danger: Color(red: 0.851, green: 0.365, blue: 0.306),        // #D95D4E
        info: Color(red: 0.459, green: 0.655, blue: 0.847),          // #75A7D8
        badge: Color(red: 0.227, green: 0.208, blue: 0.165),         // #3A352A
        badgeInk: Color(red: 0.804, green: 0.776, blue: 0.722),      // #CDC6B8
        terminalBg: Color(red: 0.063, green: 0.055, blue: 0.039),    // #100E0A
        terminalInk: Color(red: 0.780, green: 0.749, blue: 0.682)    // #C7BFAE
    )

    /// Light — warm paper, dark ink, rust accent.
    static let light = Palette(
        canvas: Color(red: 0.965, green: 0.953, blue: 0.933),        // #F6F3EE
        ink: Color(red: 0.145, green: 0.133, blue: 0.114),           // #25221D
        inkSecondary: Color(red: 0.408, green: 0.384, blue: 0.337),  // #686256
        inkTertiary: Color(red: 0.565, green: 0.533, blue: 0.475),   // #908879
        accent: Color(red: 0.749, green: 0.408, blue: 0.208),        // #BF6835
        accentSoft: Color(red: 0.749, green: 0.408, blue: 0.208, opacity: 0.14),
        panel: Color(red: 1.0, green: 0.996, blue: 0.984),           // #FFFEFA
        panelRaised: Color(red: 1.0, green: 1.0, blue: 1.0),
        footer: Color(red: 0.937, green: 0.922, blue: 0.898),        // #EFEBE5
        separator: Color(red: 0.871, green: 0.851, blue: 0.816),     // #DED9D0
        selection: Color(red: 0.749, green: 0.408, blue: 0.208, opacity: 0.28),
        success: Color(red: 0.34, green: 0.57, blue: 0.30),
        warning: Color(red: 0.75, green: 0.55, blue: 0.13),
        danger: Color(red: 0.78, green: 0.29, blue: 0.25),
        info: Color(red: 0.24, green: 0.47, blue: 0.75),
        badge: Color(red: 0.871, green: 0.851, blue: 0.816),         // #DED9D0
        badgeInk: Color(red: 0.408, green: 0.384, blue: 0.337),
        terminalBg: Color(red: 0.925, green: 0.906, blue: 0.874),    // #ECE7DF
        terminalInk: Color(red: 0.20, green: 0.19, blue: 0.16)
    )
}
