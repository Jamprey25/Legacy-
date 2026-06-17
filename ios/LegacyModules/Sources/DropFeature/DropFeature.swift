import APIClient
import DesignSystem
import LocationEngine
import SwiftUI

/// V1 Pin and V2 Treasure Chest drop flows.
public enum DropFeature {
    public static let version = "0.1.0"
}

public struct DropFeatureRootView: View {
    public init(coordinator: DropCoordinator) {
        self.coordinator = coordinator
    }

    @Bindable private var coordinator: DropCoordinator

    public var body: some View {
        VStack(spacing: LegacySpacing.lg) {
            ContentUnavailableView(
                "Drop",
                systemImage: "mappin.and.ellipse",
                description: Text("Pin a memory at your current location.")
            )

            statusView

            if case .succeeded = coordinator.state {
                Button("Drop another") { coordinator.reset() }
                    .buttonStyle(.legacySecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LegacyColor.background)
    }

    @ViewBuilder
    private var statusView: some View {
        switch coordinator.state {
        case .idle:
            EmptyView()
        case .stripping, .creating, .uploading:
            ProgressView("Dropping memory…")
                .tint(LegacyColor.accent)
        case .succeeded:
            Text("Memory dropped.")
                .font(LegacyFont.callout)
                .foregroundStyle(LegacyColor.accent)
        case .failed(let message):
            Text(message)
                .font(LegacyFont.callout)
                .foregroundStyle(LegacyColor.danger)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LegacySpacing.lg)
        }
    }
}
