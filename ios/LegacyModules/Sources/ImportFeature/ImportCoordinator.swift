import APIClient
import DropFeature
import Foundation

public enum ImportPhase: Sendable, Equatable {
    case idle
    case scanning
    case ready
    case importing(current: Int, total: Int)
    case completed(importedCount: Int)
    case failed(String)
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
        geoSamples = []

        do {
            let samples = try await PHAssetMetadataFetcher.fetchGeoSamples()
            geoSamples = samples
            geoSampleCount = samples.count
            clusters = PhotoClusterEngine.cluster(samples: samples)
            phase = clusters.isEmpty ? .failed("No geotagged photos found in your library.") : .ready
        } catch PHAssetMetadataError.unauthorized {
            phase = .failed("Photo access is off. Enable it in Settings to import.")
        } catch {
            phase = .failed("Could not scan your library. Try again.")
        }
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

        phase = .importing(current: 0, total: chosen.count)

        do {
            let request = ImportMemoriesRequest(
                idempotencyKey: Self.idempotencyKey(for: chosen),
                clusters: chosen.map { cluster in
                    ImportClusterInput(
                        lat: cluster.centroidLat,
                        lng: cluster.centroidLng,
                        capturedAt: Self.capturedAtISO(for: cluster, samples: geoSamples),
                        assetCount: cluster.photoCount
                    )
                }
            )

            let response = try await apiClient.importMemories(request)
            var uploaded = 0
            let sortedItems = response.memories.sorted { $0.clusterIndex < $1.clusterIndex }

            for (progressIndex, item) in sortedItems.enumerated() {
                phase = .importing(current: progressIndex, total: sortedItems.count)

                guard item.clusterIndex < chosen.count else { continue }

                let cluster = chosen[item.clusterIndex]
                #if os(iOS)
                guard let assetID = cluster.sampleIDs.first else { continue }
                let raw = try await PHAssetImageFetcher.loadJPEGData(assetID: assetID)
                let stripped = try EXIFStripper.stripMetadata(from: raw)
                try await mediaUploader.upload(
                    memoryID: item.memoryID,
                    data: stripped,
                    contentType: "image/jpeg",
                    signedPutURL: item.upload?.signedPutURL
                )
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
