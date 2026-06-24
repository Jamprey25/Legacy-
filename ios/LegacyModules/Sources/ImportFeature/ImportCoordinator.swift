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

public struct ImportScanProgress: Sendable, Equatable {
    public let scanned: Int
    public let total: Int
    public let found: Int

    public init(scanned: Int, total: Int, found: Int) {
        self.scanned = scanned
        self.total = total
        self.found = found
    }
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
    public private(set) var scanProgress: ImportScanProgress?

    private let initialRegionResolveLimit = 50
    private var inFlightRegionClusterIDs: Set<String> = []

    /// Longest-edge cap (pixels) for uploaded photos. Downsampling to this size at decode time is
    /// what keeps the import loop's memory flat no matter how many photos a visit has — without it
    /// a large visit decodes full-resolution bitmaps in a tight loop and the app gets jetsam-killed.
    /// 1280px is plenty for viewing a memory on any phone screen (iPhone screens top out ~1290px
    /// wide) and keeps each photo ~300KB instead of ~3MB — ~10x more capacity before storage fills.
    /// See `EXIFStripper.downsampledStrippedJPEG`.
    private static let maxUploadPixelSize = 1280

    /// How many memory upload pipelines run at once during import. Bounded so the CPU can decode
    /// the next hero while the network uploads the current one, *without* firing every decode
    /// simultaneously — the cap limits both concurrent decodes (memory) and in-flight sockets.
    /// 3 keeps peak transient memory ~3×50 MB even on older devices. Tunable.
    private static let maxConcurrentMemoryUploads = 3

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
        geoSampleCount = 0
        scanProgress = ImportScanProgress(scanned: 0, total: PHAssetMetadataFetcher.maxAssetsToScan, found: 0)

        do {
            let samples = try await PHAssetMetadataFetcher.fetchGeoSamples { [weak self] scanned, total, found in
                self?.scanProgress = ImportScanProgress(scanned: scanned, total: total, found: found)
            }
            geoSamples = samples
            geoSampleCount = samples.count
            clusters = PhotoClusterEngine.cluster(samples: samples)
            phase = clusters.isEmpty ? .failed("No geotagged photos found in your library.") : .ready
            scanProgress = nil
            if !clusters.isEmpty {
                // Prime the top-ranked clusters quickly, then resolve additional rows lazily
                // as the user drills down and scrolls.
                Task { await resolveRegions() }
            }
        } catch PHAssetMetadataError.unauthorized {
            scanProgress = nil
            phase = .failed("Photo access is off. Enable it in Settings to import.")
        } catch {
            scanProgress = nil
            phase = .failed("Could not scan your library. Try again.")
        }
    }

    /// Prime only the highest-value visits first so the browser is usable quickly.
    public func resolveRegions() async {
        let prioritized = clusters.sorted { $0.score > $1.score }
        let initialIDs = prioritized.prefix(initialRegionResolveLimit).map(\.id)
        await resolveRegions(for: initialIDs)
    }

    /// Lazily geocode a subset of clusters (e.g. the rows currently visible on screen).
    public func resolveRegions(for clusterIDs: [String]) async {
        let wantedIDs = Set(clusterIDs)
        let pending = clusters.filter {
            wantedIDs.contains($0.id) &&
                clusterRegions[$0.id] == nil &&
                !inFlightRegionClusterIDs.contains($0.id)
        }
        guard !pending.isEmpty else { return }

        isResolvingRegions = true
        pending.forEach { inFlightRegionClusterIDs.insert($0.id) }
        defer {
            pending.forEach { inFlightRegionClusterIDs.remove($0.id) }
            isResolvingRegions = !inFlightRegionClusterIDs.isEmpty
        }

        for cluster in pending {
            let region = await PlaceNameResolver.shared.region(
                lat: cluster.centroidLat,
                lng: cluster.centroidLng
            ) ?? .unknown
            clusterRegions[cluster.id] = region
        }
    }

    public func placeName(for clusterID: String) -> String? {
        guard let region = clusterRegions[clusterID] else { return nil }
        if !region.city.isEmpty { return region.city }
        if !region.admin.isEmpty { return region.admin }
        return region.country.isEmpty ? nil : region.country
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
            let sortedItems = response.memories.sorted { $0.clusterIndex < $1.clusterIndex }
            let totalPhotos = max(1, sortedItems.reduce(0) { $0 + max(1, $1.mediaCount) })
            var uploaded = 0
            phase = .importing(current: 0, total: totalPhotos)

            #if os(iOS)
            let maxPixel = Self.maxUploadPixelSize

            // Build the work list on the main actor (reads `chosen` + `geoSamples`). Each job carries
            // only Sendable values, so it can be processed entirely off the main actor in a child task.
            let jobs: [ImportJob] = sortedItems.compactMap { item in
                guard item.clusterIndex < chosen.count else { return nil }
                let cluster = chosen[item.clusterIndex]
                return ImportJob(
                    clusterIndex: item.clusterIndex,
                    memoryID: item.memoryID,
                    mediaCount: item.mediaCount,
                    signedPutURL: item.upload?.signedPutURL,
                    sampleIDs: cluster.sampleIDs,
                    lat: cluster.centroidLat,
                    lng: cluster.centroidLng,
                    dropDate: String(Self.capturedAtISO(for: cluster, samples: geoSamples).prefix(10))
                )
            }

            // Bounded concurrency: keep up to `maxConcurrentMemoryUploads` memory pipelines in flight
            // so the CPU decodes the next hero while the network uploads the current one. Memories
            // finish out of order; progress is photo-counted (not byte-tracked) and committed on the
            // main actor as each pipeline returns, so the bar stays monotonic and the pin/cache writes
            // stay serialized on the main actor.
            var uploadedPhotos = 0
            var completedPins: [(clusterIndex: Int, pin: CachedOwnPin)] = []
            await withTaskGroup(of: ImportJobResult.self) { group in
                var submitted = 0
                let maxConcurrent = min(Self.maxConcurrentMemoryUploads, jobs.count)
                while submitted < maxConcurrent {
                    let job = jobs[submitted]
                    submitted += 1
                    group.addTask { [apiClient, mediaUploader] in
                        await Self.processImportJob(job, maxPixel: maxPixel, apiClient: apiClient, mediaUploader: mediaUploader)
                    }
                }
                while let result = await group.next() {
                    uploadedPhotos += result.photosCounted
                    phase = .importing(current: min(uploadedPhotos, totalPhotos), total: totalPhotos)
                    if result.succeeded {
                        let pin = CachedOwnPin(
                            memoryID: result.memoryID,
                            lat: result.lat,
                            lng: result.lng,
                            dropDate: result.dropDate,
                            thumbnailURL: nil,
                            cachedAt: Date()
                        )
                        OwnMemoryPinCache.save(pin)
                        completedPins.append((clusterIndex: result.clusterIndex, pin: pin))
                        uploaded += 1
                    }
                    if submitted < jobs.count {
                        let job = jobs[submitted]
                        submitted += 1
                        group.addTask { [apiClient, mediaUploader] in
                            await Self.processImportJob(job, maxPixel: maxPixel, apiClient: apiClient, mediaUploader: mediaUploader)
                        }
                    }
                }
            }
            pendingCelebrationPins = completedPins
                .sorted { $0.clusterIndex < $1.clusterIndex }
                .map(\.pin)
            #else
            uploaded = sortedItems.count
            #endif

            phase = .completed(importedCount: uploaded)
            selectedClusterIDs = []
        } catch {
            phase = .failed("Import failed. Check connectivity and try again.")
        }
    }

    #if os(iOS)
    /// Self-contained, Sendable description of one memory's upload work. Built on the main actor;
    /// processed entirely off it. Flattened to primitives so no MainActor state crosses the boundary.
    private struct ImportJob: Sendable {
        let clusterIndex: Int
        let memoryID: String
        let mediaCount: Int
        let signedPutURL: String?
        let sampleIDs: [String]
        let lat: Double
        let lng: Double
        let dropDate: String
    }

    /// Result of one memory pipeline, applied back on the main actor (progress + pin/cache writes).
    private struct ImportJobResult: Sendable {
        let clusterIndex: Int
        let photosCounted: Int
        let succeeded: Bool
        let memoryID: String
        let lat: Double
        let lng: Double
        let dropDate: String
    }

    /// Runs a single memory's upload pipeline **off the main actor** (it's `nonisolated`, so it
    /// executes on the global executor). Loads → downsamples/strips → uploads the hero, then streams
    /// the extras through the background `URLSession`. Never throws out: a failed hero skips just this
    /// memory (still counts its photos so the bar completes); a failed extra is best-effort.
    private nonisolated static func processImportJob(
        _ job: ImportJob,
        maxPixel: Int,
        apiClient: LegacyAPIClient,
        mediaUploader: MemoryMediaUploader
    ) async -> ImportJobResult {
        // mediaCount is the server-accepted count (clamped); positions 0..mediaCount-1 map to slots.
        let assetIDs = Array(job.sampleIDs.prefix(job.mediaCount))
        let counted = assetIDs.count
        func result(succeeded: Bool) -> ImportJobResult {
            ImportJobResult(
                clusterIndex: job.clusterIndex,
                photosCounted: counted,
                succeeded: succeeded,
                memoryID: job.memoryID,
                lat: job.lat,
                lng: job.lng,
                dropDate: job.dropDate
            )
        }

        guard let heroID = assetIDs.first else { return result(succeeded: false) }

        // Hero (position 0) drives discovery, the thumbnail, and the celebration pin. If it can't
        // be prepared or uploaded, skip just this memory rather than sinking the whole batch.
        do {
            let heroRaw = try await PHAssetImageFetcher.loadImageData(assetID: heroID)
            let heroStripped = try EXIFStripper.downsampledStrippedJPEG(from: heroRaw, maxPixelSize: maxPixel)
            try await mediaUploader.upload(
                memoryID: job.memoryID,
                data: heroStripped,
                contentType: "image/jpeg",
                signedPutURL: job.signedPutURL,
                position: 0
            )
        } catch {
            return result(succeeded: false)
        }

        // Extras stream up via the background URLSession: handed to the OS so they keep uploading
        // after this screen is gone and survive app suspension. Best-effort — a failed extra never
        // sinks the memory. Yield between extras to prevent memory spikes from loading all images at once.
        for (position, assetID) in assetIDs.enumerated().dropFirst() {
            do {
                let raw = try await PHAssetImageFetcher.loadImageData(assetID: assetID)
                let stripped = try EXIFStripper.downsampledStrippedJPEG(from: raw, maxPixelSize: maxPixel)
                let request = try apiClient.directUploadRequest(
                    memoryID: job.memoryID,
                    contentType: "image/jpeg",
                    position: position
                )
                try BackgroundMediaUploader.shared.enqueue(request: request, data: stripped)
                try? await Task.sleep(for: .milliseconds(50))
            } catch {
                // skip this photo
            }
        }

        return result(succeeded: true)
    }
    #endif

    public func reset() {
        phase = .idle
        clusters = []
        geoSamples = []
        geoSampleCount = 0
        selectedClusterIDs = []
        clusterRegions = [:]
        scanProgress = nil
        inFlightRegionClusterIDs = []
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
