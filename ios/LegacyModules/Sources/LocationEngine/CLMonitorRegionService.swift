#if os(iOS)
import CoreLocation
import Foundation

/// iOS 17+ `CLMonitor` wrapper for circular geographic conditions.
@available(iOS 17.0, *)
public actor CLMonitorRegionService {
    public enum Event: Sendable {
        case satisfied(identifier: String)
        case unsatisfied(identifier: String)
    }

    private let monitor: CLMonitor
    private var armedIDs: Set<String> = []

    /// Monitor names must be alphanumeric (WWDC23 — no `.`, `:`, or `-`).
    public init(name: String = "legacyRegions") async {
        monitor = await CLMonitor(name)
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

    public func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    for try await event in await monitor.events {
                        switch event.state {
                        case .satisfied:
                            continuation.yield(.satisfied(identifier: event.identifier))
                        case .unsatisfied:
                            continuation.yield(.unsatisfied(identifier: event.identifier))
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
#endif
