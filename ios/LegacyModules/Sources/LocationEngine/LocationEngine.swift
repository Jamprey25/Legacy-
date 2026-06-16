import CoreLocation
import Foundation

public enum LocationEngineError: Error, Sendable {
    case unauthorized
    case fixUnavailable
    case accuracyRejected
}

/// Foreground fix acquisition, accuracy reporting, and movement-gated scan eligibility.
@MainActor
public protocol LocationEngineProtocol: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
    func acquireFix() async throws -> CLLocation
}

public enum ScanMovementGate {
    /// Returns true when the user moved >25m or >30s elapsed since last scan-eligible fix.
    public static func shouldTriggerScan(
        for location: CLLocation,
        lastScanLocation: CLLocation?,
        lastScanDate: Date?
    ) -> Bool {
        let now = Date()

        if let lastScanDate, now.timeIntervalSince(lastScanDate) > 30 {
            return true
        }

        if let lastScanLocation, location.distance(from: lastScanLocation) > 25 {
            return true
        }

        return lastScanLocation == nil
    }
}

@MainActor
@Observable
public final class LocationEngine: NSObject, LocationEngineProtocol {
    public private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    public private(set) var latestLocation: CLLocation?

    private let manager: CLLocationManager
    private var fixContinuation: CheckedContinuation<CLLocation, Error>?

    public override init() {
        self.manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    public func requestWhenInUseAuthorization() {
        #if os(iOS)
        manager.requestWhenInUseAuthorization()
        #endif
    }

    public func acquireFix() async throws -> CLLocation {
        #if os(iOS)
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            throw LocationEngineError.unauthorized
        }
        #endif

        return try await withCheckedThrowingContinuation { continuation in
            fixContinuation = continuation
            manager.requestLocation()
        }
    }
}

extension LocationEngine: CLLocationManagerDelegate {
    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            latestLocation = location
            fixContinuation?.resume(returning: location)
            fixContinuation = nil
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            fixContinuation?.resume(throwing: error)
            fixContinuation = nil
        }
    }
}
