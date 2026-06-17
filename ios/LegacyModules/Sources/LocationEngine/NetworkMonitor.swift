import Foundation
import Network

/// Observes device connectivity for offline-but-near Wander UX (DEC-29).
@MainActor
@Observable
public final class NetworkMonitor {
    public static let shared = NetworkMonitor()

    public private(set) var isOffline = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.legacy.network-monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOffline = path.status != .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    public func start() {
        isOffline = monitor.currentPath.status != .satisfied
    }
}
