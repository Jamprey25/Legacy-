#if os(iOS)
import CoreLocation
import Foundation

/// iOS 17+ `CLMonitor` wrapper for circular geographic conditions.
///
/// **One process-wide instance only.** Core Location allows a single open `CLMonitor`
/// per name; concurrent or repeated `CLMonitor("legacyRegions")` calls abort with
/// `NSInternalInconsistencyException` ("already in use"). Use `shared()` everywhere.
@available(iOS 17.0, *)
public actor CLMonitorRegionService {
    /// Serializes first-time monitor creation across concurrent callers.
    private actor SharedAccess {
        static let shared = SharedAccess()

        private var cached: CLMonitorRegionService?
        private var pending: Task<CLMonitorRegionService, Never>?

        func instance() async -> CLMonitorRegionService {
            if let cached { return cached }
            if let pending { return await pending.value }
            let task = Task { await CLMonitorRegionService() }
            pending = task
            let service = await task.value
            cached = service
            pending = nil
            return service
        }
    }

    public static func shared() async -> CLMonitorRegionService {
        await SharedAccess.shared.instance()
    }

    private let monitor: CLMonitor
    private var armedIDs: Set<String> = []
    private var eventsTask: Task<Void, Never>?
    private var onSatisfied: (@Sendable (String) async -> Void)?

    /// Monitor names must be alphanumeric (WWDC23 — no `.`, `:`, or `-`).
    private init(name: String = "legacyRegions") async {
        monitor = await CLMonitor(name)
        startEventsIfNeeded()
    }

    /// Wire region-entry handling. Safe to call whenever the coordinator (re)appears.
    public func setOnSatisfied(_ handler: (@Sendable (String) async -> Void)?) {
        onSatisfied = handler
    }

    public func syncRegions(_ slots: [RegionSlot]) async {
        let desired = Set(slots.map(\.id))
        for id in armedIDs.subtracting(desired) {
            await monitor.remove(id)
        }

        let existing = Set(await monitor.identifiers)
        for slot in slots {
            guard !existing.contains(slot.id) || !armedIDs.contains(slot.id) else { continue }
            let coord = slot.coordinate
            let condition = CLMonitor.CircularGeographicCondition(
                center: CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lng),
                radius: slot.radiusM
            )
            await monitor.add(condition, identifier: slot.id, assuming: .unsatisfied)
        }

        armedIDs = desired
    }

    private func startEventsIfNeeded() {
        guard eventsTask == nil else { return }
        eventsTask = Task {
            do {
                for try await event in await monitor.events {
                    guard !Task.isCancelled else { break }
                    if event.state == .satisfied {
                        await onSatisfied?(event.identifier)
                    }
                }
            } catch {
                // Monitor cancelled or torn down.
            }
        }
    }
}
#endif
