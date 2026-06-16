import APIClient
import DesignSystem
import LocationEngine
import SwiftUI

/// V1 Pin and V2 Treasure Chest drop flows.
public enum DropFeature {
    public static let version = "0.1.0"
}

@MainActor
@Observable
public final class DropCoordinator {
    public init(
        apiClient: LegacyAPIClient,
        locationEngine: LocationEngine
    ) {
        self.apiClient = apiClient
        self.locationEngine = locationEngine
    }

    private let apiClient: LegacyAPIClient
    private let locationEngine: LocationEngine

    public var isDropping = false
}

public struct DropFeatureRootView: View {
    public init(coordinator: DropCoordinator) {
        self.coordinator = coordinator
    }

    @Bindable private var coordinator: DropCoordinator

    public var body: some View {
        ContentUnavailableView(
            "Drop",
            systemImage: "mappin.and.ellipse",
            description: Text("Pin drop flow — M1")
        )
    }
}
