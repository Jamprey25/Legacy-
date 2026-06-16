import CoreLocation
import Foundation

public enum LocationEngineError: Error, Sendable {
    case unauthorized
    case fixUnavailable
    case accuracyRejected
    case superseded
}

/// A point fix reduced to exactly what the API contract accepts: `lat`, `lng`, `accuracy_m`.
/// Deliberately carries no heading/course/speed — the client never holds a movement vector
/// (SEC-LOC-1: no position trail).
public struct LocationFix: Sendable, Equatable {
    public let lat: Double
    public let lng: Double
    public let accuracyM: Double
    public let timestamp: Date

    public init(lat: Double, lng: Double, accuracyM: Double, timestamp: Date) {
        self.lat = lat
        self.lng = lng
        self.accuracyM = accuracyM
        self.timestamp = timestamp
    }

    public init(_ location: CLLocation) {
        self.lat = location.coordinate.latitude
        self.lng = location.coordinate.longitude
        self.accuracyM = location.horizontalAccuracy
        self.timestamp = location.timestamp
    }
}

/// Foreground fix acquisition, accuracy reporting, and movement-gated scan eligibility.
@MainActor
public protocol LocationEngineProtocol: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
    func acquireFix() async throws -> LocationFix
}

public enum ScanMovementGate {
    /// Distance (meters) the user must move to re-trigger a scan.
    public static let distanceThresholdM: CLLocationDistance = 25
    /// Elapsed time (seconds) after which a scan re-triggers regardless of movement.
    public static let timeThresholdS: TimeInterval = 30

    /// Returns true when the user moved >25m or >30s elapsed since last scan-eligible fix.
    /// The very first fix (no prior scan) always triggers.
    public static func shouldTriggerScan(
        for location: CLLocation,
        lastScanLocation: CLLocation?,
        lastScanDate: Date?,
        now: Date = Date()
    ) -> Bool {
        if lastScanLocation == nil { return true }

        if let lastScanDate, now.timeIntervalSince(lastScanDate) > timeThresholdS {
            return true
        }

        if let lastScanLocation, location.distance(from: lastScanLocation) > distanceThresholdM {
            return true
        }

        return false
    }
}

@MainActor
@Observable
public final class LocationEngine: NSObject, LocationEngineProtocol {
    public private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// Most recent fix observed (foreground). Cleared is fine — never persisted to disk.
    public private(set) var latestFix: LocationFix?

    private let manager: CLLocationManager
    private var fixContinuation: CheckedContinuation<LocationFix, Error>?

    // Movement-gate bookkeeping. Held in memory only.
    private var lastScanLocation: CLLocation?
    private var lastScanDate: Date?

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

    public func acquireFix() async throws -> LocationFix {
        #if os(iOS)
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            throw LocationEngineError.unauthorized
        }
        #endif

        // A new request supersedes any in-flight one so the old continuation can't leak.
        fixContinuation?.resume(throwing: LocationEngineError.superseded)
        fixContinuation = nil

        return try await withCheckedThrowingContinuation { continuation in
            fixContinuation = continuation
            manager.requestLocation()
        }
    }

    /// Whether a fix is far/old enough from the last scan to warrant a new `/scan` call.
    public func shouldScan(for location: CLLocation, now: Date = Date()) -> Bool {
        ScanMovementGate.shouldTriggerScan(
            for: location,
            lastScanLocation: lastScanLocation,
            lastScanDate: lastScanDate,
            now: now
        )
    }

    /// Record that a scan was performed at this location (resets the movement gate).
    public func recordScan(at location: CLLocation, date: Date = Date()) {
        lastScanLocation = location
        lastScanDate = date
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
            let fix = LocationFix(location)
            latestFix = fix
            fixContinuation?.resume(returning: fix)
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
