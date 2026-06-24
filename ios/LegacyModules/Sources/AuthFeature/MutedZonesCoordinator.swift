import APIClient
import Foundation

#if os(iOS)

@MainActor
@Observable
public final class MutedZonesCoordinator {
    public private(set) var zones: [MutedZone] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let apiClient: LegacyAPIClient

    public init(apiClient: LegacyAPIClient) {
        self.apiClient = apiClient
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            zones = try await apiClient.listMutedZones()
        } catch {
            errorMessage = "Couldn't load muted zones."
        }
    }

    public func addZone(lat: Double, lng: Double, radiusM: Int, label: String?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let zone = try await apiClient.createMutedZone(
                CreateMutedZoneRequest(lat: lat, lng: lng, radiusM: radiusM, label: label)
            )
            zones.append(zone)
        } catch let LegacyAPIError.invalidRequest(_, message) {
            errorMessage = message
        } catch {
            errorMessage = "Couldn't save zone. Check your connection."
        }
    }

    public func deleteZone(id: String) async {
        do {
            try await apiClient.deleteMutedZone(id: id)
            zones.removeAll { $0.id == id }
        } catch {
            errorMessage = "Couldn't delete zone."
        }
    }
}

#endif
