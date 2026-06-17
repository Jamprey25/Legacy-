#if os(iOS)
import CoreLocation
import Foundation

public enum BackgroundLocationPhase: Sendable, Equatable {
    case idle
    case monitoring
    case rotating
    case regionEntered(identifier: String)
    case failed(String)
}

/// M4 background proximity scaffold: significant-change wakes → rotate CLMonitor regions → terminate.
@MainActor
@Observable
public final class BackgroundLocationCoordinator: NSObject {
    public var phase: BackgroundLocationPhase = .idle
    public var armedRegionCount = 0

    public var onRegionEntered: ((String) async -> Void)?

    private let manager: CLLocationManager
    private var regionService: CLMonitorRegionService?
    private var eventTask: Task<Void, Never>?

    public override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .otherNavigation
    }

    public var isAuthorizedForBackground: Bool {
        manager.authorizationStatus == .authorizedAlways
    }

    public func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// Start significant-change monitoring (near-zero steady-state power).
    public func startIfAuthorized() async {
        guard isAuthorizedForBackground else {
            phase = .idle
            return
        }

        if #available(iOS 17.0, *), regionService == nil {
            regionService = await CLMonitorRegionService()
            startEventLoopIfNeeded()
        }

        #if !targetEnvironment(simulator)
        manager.startMonitoringSignificantLocationChanges()
        #endif
        phase = .monitoring
    }

    public func stop() {
        manager.stopMonitoringSignificantLocationChanges()
        eventTask?.cancel()
        eventTask = nil
        phase = .idle
        armedRegionCount = 0
    }

    /// Re-arm regions around the latest fix (called on significant-change wake).
    public func rotateRegions(around reference: CLLocationCoordinate2D) async {
        phase = .rotating
        let ownPins = OwnMemoryPinCache.load()
        let coarse = CoarseZoneCache.load()
        let slots = RegionRotationPolicy.rotate(
            reference: reference,
            ownPins: ownPins,
            coarseZones: coarse
        )

        if #available(iOS 17.0, *), let regionService {
            await regionService.syncRegions(slots)
            armedRegionCount = slots.count
            phase = .monitoring
        } else {
            phase = .failed("Background regions require iOS 17.")
        }
    }

    /// Manual trigger for tests / Simulator.
    public func rotateNow() async {
        if let fix = manager.location?.coordinate {
            await rotateRegions(around: fix)
            return
        }
        manager.requestLocation()
    }

    @available(iOS 17.0, *)
    private func startEventLoopIfNeeded() {
        guard eventTask == nil, let regionService else { return }
        let service = regionService
        eventTask = Task { [weak self] in
            for await event in await service.events() {
                guard !Task.isCancelled else { break }
                switch event {
                case .satisfied(let id):
                    await MainActor.run { self?.phase = .regionEntered(identifier: id) }
                    if let self { await self.onRegionEntered?(id) }
                case .unsatisfied:
                    break
                }
            }
        }
    }
}

extension BackgroundLocationCoordinator: CLLocationManagerDelegate {
    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            await rotateRegions(around: location.coordinate)
        }
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if isAuthorizedForBackground {
                await startIfAuthorized()
            } else {
                stop()
            }
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            phase = .failed(error.localizedDescription)
        }
    }
}
#endif
