import DesignSystem
import SwiftUI

/// Pre-TestFlight education sheet before `requestAlwaysAuthorization()` (engineering-plan §7).
public struct BackgroundDiscoveryPermissionSheet: View {
    public var onEnable: () -> Void
    public var onDismiss: () -> Void

    public init(onEnable: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onEnable = onEnable
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: LegacySpacing.lg) {
            Image(systemName: "bell.badge")
                .font(.system(size: 40))
                .foregroundStyle(LegacyColor.accent)

            Text("Discover memories in the background")
                .font(LegacyFont.title)
                .foregroundStyle(LegacyColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(
                "Legacy uses low-power location (not continuous GPS) to re-arm nearby places and notify you when you return to a memory. You can change this anytime in Settings."
            )
            .font(LegacyFont.callout)
            .foregroundStyle(LegacyColor.textSecondary)
            .multilineTextAlignment(.center)

            Button("Enable background discovery", action: onEnable)
                .buttonStyle(.legacyPrimary)

            Button("Not now", action: onDismiss)
                .buttonStyle(.legacySecondary)
        }
        .padding(LegacySpacing.xl)
        .background(LegacyColor.background)
    }
}
