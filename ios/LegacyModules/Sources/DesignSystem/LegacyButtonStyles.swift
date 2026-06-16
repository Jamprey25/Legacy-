import SwiftUI

/// Filled accent button for primary actions (Drop, Unlock, Sign in).
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LegacyFont.headline)
            .foregroundStyle(LegacyColor.textOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LegacySpacing.md)
            .padding(.horizontal, LegacySpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: LegacyRadius.md, style: .continuous)
                    .fill(configuration.isPressed ? LegacyColor.accentDeep : LegacyColor.accent)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Outline button for secondary actions.
public struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LegacyFont.headline)
            .foregroundStyle(LegacyColor.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LegacySpacing.md)
            .padding(.horizontal, LegacySpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: LegacyRadius.md, style: .continuous)
                    .stroke(LegacyColor.separator, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    public static var legacyPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    public static var legacySecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
