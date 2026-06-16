import SwiftUI

/// Semantic color palette. Dark-first; warmth accent drives the proximity cue.
public enum LegacyColor {
    /// Deep near-black canvas for Wander/map surfaces.
    public static let background = Color(red: 0.06, green: 0.06, blue: 0.08)
    /// Slightly raised surface for cards and sheets.
    public static let surface = Color(red: 0.11, green: 0.11, blue: 0.14)
    /// Hairline separators and inactive strokes.
    public static let separator = Color.white.opacity(0.10)

    /// Primary warmth accent — also the warmth-cue hue.
    public static let accent = Color(red: 0.95, green: 0.72, blue: 0.45)
    /// Pressed/active accent.
    public static let accentDeep = Color(red: 0.86, green: 0.55, blue: 0.30)

    public static let textPrimary = Color.white.opacity(0.95)
    public static let textSecondary = Color.white.opacity(0.62)
    public static let textOnAccent = Color(red: 0.10, green: 0.07, blue: 0.04)

    public static let danger = Color(red: 0.90, green: 0.36, blue: 0.34)
}
