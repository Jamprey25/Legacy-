import SwiftUI

/// Shared typography, colors, spacing, and warmth-cue components.
/// Warmth gradient is screen-edge ambient only — never directional (DEC-15).
public enum DesignSystem {
    public static let version = "0.1.0"
}

public struct LegacyColors {
    public static let background = Color(red: 0.06, green: 0.06, blue: 0.08)
    public static let accent = Color(red: 0.95, green: 0.72, blue: 0.45)

    public init() {}
}

public struct LegacyTypography {
    public static let title = Font.system(.title, design: .rounded, weight: .semibold)
    public static let body = Font.system(.body, design: .default)

    public init() {}
}

/// Non-directional screen-edge ambient gradient. Intensity only — no bearing.
public struct WarmthCueOverlay: View {
    private let intensity: Double

    public init(intensity: Double) {
        self.intensity = min(max(intensity, 0), 1)
    }

    public var body: some View {
        LinearGradient(
            colors: [
                LegacyColors.accent.opacity(intensity * 0.35),
                .clear,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
