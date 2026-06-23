import APIClient
import DropFeature
import Foundation
import LocationEngine

public enum ImportPhase: Sendable, Equatable {
    case idle
    case scanning
    case ready
    case importing(current: Int, total: Int)
    case completed(importedCount: Int)
    case failed(String)
}

/// Administrative location for a visit, used by the Country → State → City → visits
/// import drill-down. Empty components fall back to the nearest known level for display.
public struct ImportRegion: Sendable, Equatable, Hashable {
    public let country: String
    public let admin: String
    public let city: String

    public init(country: String, admin: String, city: String) {
        self.country = country
        self.admin = admin
        self.city = city
    }

    /// Resolved but with no usable name (geocoder returned nothing useful).
    public static let unknown = ImportRegion(country: "Unknown location", admin: "", city: "")
}

@MainActor
@Observable
public final class ImportCoordinator {
    public init(
        apiClient: LegacyAPIClient,
        mediaUploader: MemoryMediaUploader? = nil
    ) {
        self.apiClient = apiClient
        self.mediaUploader = mediaUploader ?? MemoryMediaUploader(apiClient: apiClient)
    }

    private let apiClient: LegacyAPIClient
    private let mediaUploader: MemoryMediaUploader
    private var geoSamples: [PhotoGeoSample] = []
    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public private(set) var phase: ImportPhase = .idle
    public private(set) var clusters: [PhotoCluster] = []
    public private(set) var geoSampleCount = 0
    public var selectedClusterIDs: Set<String> = []

    /// Resolved location per cluster ID. Fills in progressively after a scan; a cluster
    /// absent from this map is still "Locating…". Drives the import location drill-down.
    public private(set) var clusterRegions: [String: ImportRegion] = [:]
    public private(set) var isResolvingRegions = false

    public private(set) var pendingCelebrationPins: [CachedOwnPin] = []

    public func consumeCelebrationPins() -> [CachedOwnPin] {
        defer { pendingCelebrationPins = [] }
        return pendingCelebrationPins
    }

    public var selectedClusters: [PhotoCluster] {
        clusters.filter { selectedClusterIDs.contains($0.id) }
    }

    public var isImporting: Bool {
        if case .importing = phase { return true }
        return false
    }

    #if os(iOS)
    public func scanPhotoLibrary() async {
        guard phase != .scanning else { return }
        phase = .scanning
        selectedClusterIDs = []
        clusters = []
        clusterRegions = [:]
        geoSamples = []

        do {
            let samples = try await PHAssetMetadataFetcher.fetchGeoSamples()
            geoSamples = samples
            geoSampleCount = samples.count
            clusters = PhotoClusterEngine.cluster(samples: samples)
            phase = clusters.isEmpty ? .failed("No geotagged photos found in your library.") : .ready
            if !clusters.isEmpty {
                // Sort visits into Country/State/City in the background so the list is
                // usable immediately; rows move out of "Locating…" as they resolve.
                Task { await resolveRegions() }
            }
        } catch PHAssetMetadataError.unauthorized {
            phase = .failed("Photo access is off. Enable it in Settings to import.")
        } catch {
            phase = .failed("Could not scan your library. Try again.")
        }
    }

    /// Reverse-geocode every cluster centroid into a Country/State/City. Serialized through
    /// the resolver's actor (and its ~1.1 km bucket cache), so visits in the same area share
    /// a single geocoder request and we stay clear of CLGeocoder's rate limit.
    public func resolveRegions() async {
        let pending = clusters.filter { clusterRegions[$0.id] == nil }
        guard !pending.isEmpty else { return }
        isResolvingRegions = true
        defer { isResolvingRegions = false }

        for cluster in pending {
            let region = await PlaceNameResolver.shared.region(
                lat: cluster.centroidLat,
                lng: cluster.centroidLng
            ) ?? .unknown
            clusterRegions[cluster.id] = region
        }
    }

    public func selectClusters(_ ids: [String]) {
        selectedClusterIDs.formUnion(ids)
    }

    public func deselectClusters(_ ids: [String]) {
        selectedClusterIDs.subtract(ids)
    }
    #endif

    public func toggleSelection(_ cluster: PhotoCluster) {
        if selectedClusterIDs.contains(cluster.id) {
            selectedClusterIDs.remove(cluster.id)
        } else {
            selectedClusterIDs.insert(cluster.id)
        }
    }

    public func importSelected() async {
        let chosen = selectedClusters
        guard !chosen.isEmpty, !isImporting else { return }

        // Progress is counted in PHOTOS, not memories — a single visit can be many photos.
        let estimatedPhotos = max(1, chosen.reduce(0) { $0 + $1.photoCount })
        phase = .importing(current: 0, total: estimatedPhotos)
        pendingCelebrationPins = []

        do {
            let request = ImportMemoriesRequest(
                idempotencyKey: Self.idempotencyKey(for: chosen),
                clusters: chosen.map { cluster in
                    ImportClusterInput(
                        lat: cluster.centroidLat,
                        lng: cluster.centroidLng,
                        capturedAt: Self.capturedAtISO(for: cluster, samples: geoSamples),
                        assetCount: cluster.photoCount,
                        // Upload the whole visit — a memory holds all its photos, not one.
                        photoCount: cluster.photoCount
                    )
                }
            )

            let response = try await apiClient.importMemories(request)
            var uploaded = 0
            let sortedItems = response.memories.sorted { $0.clusterIndex < $1.clusterIndex }
            let totalPhotos = max(1, sortedItems.reduce(0) { $0 + max(1, $1.mediaCount) })
            var uploadedPhotos = 0
            phase = .importing(current: 0, total: totalPhotos)

            for item in sortedItems {
                guard item.clusterIndex < chosen.count else { continue }

                let cluster = chosen[item.clusterIndex]
                #if os(iOS)
                // Upload every photo of the visit. mediaCount is the server-accepted count
                // (clamped); positions 0..mediaCount-1 map to memory_media slots.
                let assetIDs = Array(cluster.sampleIDs.prefix(item.mediaCount))
                guard let heroID = assetIDs.first else { continue }

                // Hero (position 0) must succeed — it drives discovery, the thumbnail, and
                // the celebration pin. A throw here fails this memory.
                let heroRaw = try await PHAssetImageFetcher.loadJPEGData(assetID: heroID)
                let heroStripped = try EXIFStripper.stripMetadata(from: heroRaw)
                try await mediaUploader.upload(
                    memoryID: item.memoryID,
                    data: heroStripped,
                    contentType: "image/jpeg",
                    signedPutURL: item.upload?.signedPutURL,
                    position: 0
                )
                uploadedPhotos += 1
                phase = .importing(current: uploadedPhotos, total: totalPhotos)

                // Extras stream up via the background URLSession: handed to the OS and counted
                // as soon as they're enqueued, so they keep uploading after this screen is gone
                // and survive app suspension instead of blocking here. Best-effort — a failed
                // extra never sinks the memory, and progress still advances so the bar finishes.
                for (position, assetID) in assetIDs.enumerated().dropFirst() {
                    do {
                        let raw = try await PHAssetImageFetcher.loadJPEGData(assetID: assetID)
                        let stripped = try EXIFStripper.stripMetadata(from: raw)
                        let request = try apiClient.directUploadRequest(
                            memoryID: item.memoryID,
                            contentType: "image/jpeg",
                            position: position
                        )
                        try BackgroundMediaUploader.shared.enqueue(request: request, data: stripped)
                    } catch {
                        // skip this photo; still advance progress below
                    }
                    uploadedPhotos += 1
                    phase = .importing(current: uploadedPhotos, total: totalPhotos)
                }
                let pin = CachedOwnPin(
                    memoryID: item.memoryID,
                    lat: cluster.centroidLat,
                    lng: cluster.centroidLng,
                    dropDate: Self.capturedAtISO(for: cluster, samples: geoSamples).prefix(10).description,
                    thumbnailURL: nil,
                    cachedAt: Date()
                )
                OwnMemoryPinCache.save(pin)
                pendingCelebrationPins.append(pin)
                uploaded += 1
                #else
                uploaded += 1
                #endif
            }

            phase = .completed(importedCount: uploaded)
            selectedClusterIDs = []
        } catch {
            phase = .failed("Import failed. Check connectivity and try again.")
        }
    }

    public func reset() {
        phase = .idle
        clusters = []
        geoSamples = []
        geoSampleCount = 0
        selectedClusterIDs = []
    }

    static nonisolated func idempotencyKey(for clusters: [PhotoCluster]) -> String {
        let ids = clusters.map(\.id).sorted().joined(separator: ",")
        let day = Calendar.current.startOfDay(for: Date())
        let bucket = ISO8601DateFormatter().string(from: day).prefix(10)
        return "import:\(bucket):\(ids.hashValue)"
    }

    static nonisolated func capturedAtISO(for cluster: PhotoCluster, samples: [PhotoGeoSample]) -> String {
        let sampleMap = Dictionary(uniqueKeysWithValues: samples.map { ($0.id, $0.capturedAt) })
        let dates = cluster.sampleIDs.compactMap { sampleMap[$0] }
        let earliest = dates.min() ?? Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: earliest)
    }
}
