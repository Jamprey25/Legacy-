import APIClient
import CoreLocation
import Foundation

/// Background region entry → foreground-quality fix → `/scan` (M4, engineering-plan §7).
@MainActor
public enum BackgroundRegionScanService {
    public struct Result: Sendable {
        public let teasers: [Teaser]
        public let zones: [CoarseZone]
        public let hasInRangeMemory: Bool

        public init(teasers: [Teaser], zones: [CoarseZone] = [], hasInRangeMemory: Bool) {
            self.teasers = teasers
            self.zones = zones
            self.hasInRangeMemory = hasInRangeMemory
        }
    }

    /// Performs one scan after a CLMonitor region fires. Returns nil on location/network failure.
    public static func scanOnRegionEntry(
        regionIdentifier: String,
        apiClient: LegacyAPIClient,
        locationEngine: LocationEngine
    ) async -> Result? {
        _ = regionIdentifier
        do {
            let fix = try await locationEngine.acquireFix()
            let appAttest = await AppAttestBridge.currentAssertion()
            let body = LocationRequest(
                lat: fix.lat,
                lng: fix.lng,
                accuracyM: fix.accuracyM,
                attestation: appAttest?.attestation,
                challengeToken: appAttest?.challengeToken
            )

            if let response = try await apiClient.scan(body) {
                let inRange = response.teasers.contains { $0.inRange }
                locationEngine.recordScan(at: CLLocation(latitude: fix.lat, longitude: fix.lng))
                return Result(teasers: response.teasers, zones: response.zones, hasInRangeMemory: inRange)
            }

            return Result(teasers: [], zones: [], hasInRangeMemory: false)
        } catch {
            return nil
        }
    }
}
