import SwiftUI

/// Type scale. Rounded design for display/emotional weight; default for body/UI.
public enum LegacyFont {
    public static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    public static let title = Font.system(.title, design: .rounded, weight: .semibold)
    public static let title2 = Font.system(.title2, design: .rounded, weight: .semibold)
    public static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
    public static let body = Font.system(.body, design: .default)
    public static let callout = Font.system(.callout, design: .default)
    public static let caption = Font.system(.caption, design: .default)
    /// Monospaced digits for time-since-drop deltas in Memory Lane.
    public static let metric = Font.system(.subheadline, design: .rounded).monospacedDigit()
}
