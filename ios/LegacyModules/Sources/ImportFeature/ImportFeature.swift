import APIClient
import DesignSystem
import LocationEngine
import SwiftUI

/// On-device PHAsset clustering and batch import. GPS metadata never leaves device during clustering.
public enum ImportFeature {
    public static let version = "0.1.0"
}

@MainActor
@Observable
public final class ImportCoordinator {
    public init(
        apiClient: LegacyAPIClient,
        locationEngine: LocationEngine
    ) {
        self.apiClient = apiClient
        self.locationEngine = locationEngine
    }

    private let apiClient: LegacyAPIClient
    private let locationEngine: LocationEngine
}

public struct ImportFeatureRootView: View {
    public init(coordinator: ImportCoordinator) {
        self.coordinator = coordinator
    }

    @Bindable private var coordinator: ImportCoordinator

    public var body: some View {
        ContentUnavailableView(
            "Import",
            systemImage: "square.stack.3d.up",
            description: Text("Camera roll import — M3")
        )
    }
}
