import APIClient
import DesignSystem
import SwiftUI

/// Grid of own memories — oldest first, no proximity check for owner content.
public enum MemoryLaneFeature {
    public static let version = "0.1.0"
}

@MainActor
@Observable
public final class MemoryLaneCoordinator {
    public init(apiClient: LegacyAPIClient) {
        self.apiClient = apiClient
    }

    private let apiClient: LegacyAPIClient
}

public struct MemoryLaneFeatureRootView: View {
    public init(coordinator: MemoryLaneCoordinator) {
        self.coordinator = coordinator
    }

    @Bindable private var coordinator: MemoryLaneCoordinator

    public var body: some View {
        ContentUnavailableView(
            "Memory Lane",
            systemImage: "photo.on.rectangle.angled",
            description: Text("Your memories — M2")
        )
    }
}
