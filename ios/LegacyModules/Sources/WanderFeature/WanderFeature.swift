import APIClient
import DesignSystem
import LocationEngine
import SwiftUI

/// Wander mode: movement-gated scan loop, warmth cue, unlock flow.
/// Warmth cue is non-directional — screen-edge gradient only (DEC-15).
public enum WanderFeature {
    public static let version = "0.1.0"
}

@MainActor
@Observable
public final class WanderCoordinator {
    public init(
        apiClient: LegacyAPIClient,
        locationEngine: LocationEngine
    ) {
        self.apiClient = apiClient
        self.locationEngine = locationEngine
    }

    private let apiClient: LegacyAPIClient
    private let locationEngine: LocationEngine

    /// Ambient warmth intensity 0…1. No directional component.
    public var warmthIntensity: Double = 0
}

public struct WanderFeatureRootView: View {
    public init(coordinator: WanderCoordinator) {
        self.coordinator = coordinator
    }

    @Bindable private var coordinator: WanderCoordinator

    public var body: some View {
        ZStack {
            LegacyColors.background
                .ignoresSafeArea()

            ContentUnavailableView(
                "Wander",
                systemImage: "map",
                description: Text("Empty map — M0 demo target")
            )

            WarmthCueOverlay(intensity: coordinator.warmthIntensity)
                .ignoresSafeArea()
        }
    }
}
