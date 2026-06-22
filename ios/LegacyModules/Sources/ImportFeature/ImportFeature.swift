import APIClient
import DesignSystem
import SwiftUI

#if os(iOS)
import MapKit
import UIKit
#endif

/// On-device PHAsset clustering and batch import. GPS metadata never leaves device during clustering.
public enum ImportFeature {
    public static let version = "0.1.0"
}

public struct ImportFeatureRootView: View {
    public init(coordinator: ImportCoordinator) {
        self.coordinator = coordinator
    }

    @Bindable private var coordinator: ImportCoordinator

    public var body: some View {
        NavigationStack {
            ZStack {
                LegacyColor.background
                    .ignoresSafeArea()

                content
            }
            .navigationTitle("Import")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.phase {
        case .idle:
            idleView
        case .scanning:
            ProgressView("Scanning photo library…")
                .tint(LegacyColor.accent)
        case .ready, .importing:
            clusterExplorer
        case .completed(let count):
            completionView(count: count)
        case .failed(let message):
            failedView(message: message)
        }
    }

    private var idleView: some View {
        VStack(spacing: LegacySpacing.lg) {
            ContentUnavailableView(
                "Import memories",
                systemImage: "square.stack.3d.up",
                description: Text("Find geotagged photos and import each visit as a separate memory.")
            )
            #if os(iOS)
            Button("Scan photo library") {
                Task { await coordinator.scanPhotoLibrary() }
            }
            .buttonStyle(.legacyPrimary)
            .padding(.horizontal, LegacySpacing.xl)
            #endif
        }
    }

    // MARK: - Cluster explorer

    private var clusterExplorer: some View {
        VStack(spacing: 0) {
            if case .importing(let current, let total) = coordinator.phase {
                ProgressView(
                    "Saving \(current) of \(total) \(total == 1 ? "photo" : "photos")…",
                    value: Double(current),
                    total: Double(total)
                )
                .tint(LegacyColor.accent)
                .padding(.horizontal, LegacySpacing.lg)
                .padding(.top, LegacySpacing.sm)
            }

            Text("\(coordinator.geoSampleCount) geotagged photos → \(coordinator.clusters.count) visits")
                .font(LegacyFont.caption)
                .foregroundStyle(LegacyColor.textSecondary)
                .padding(.vertical, LegacySpacing.xs)

            #if os(iOS)
            ImportClusterMap(
                clusters: coordinator.clusters,
                selectedIDs: coordinator.selectedClusterIDs
            )
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md))
            .padding(.horizontal, LegacySpacing.lg)
            .padding(.bottom, LegacySpacing.xs)
            #endif

            clusterList

            if !coordinator.selectedClusterIDs.isEmpty {
                Button("Import \(coordinator.selectedClusterIDs.count) \(coordinator.selectedClusterIDs.count == 1 ? "memory" : "memories")") {
                    Task { await coordinator.importSelected() }
                }
                .buttonStyle(.legacyPrimary)
                .padding(.horizontal, LegacySpacing.xl)
                .padding(.vertical, LegacySpacing.sm)
                .disabled(coordinator.isImporting)
            }
        }
    }

    private var clusterList: some View {
        List {
            ForEach(clustersByYear, id: \.year) { group in
                Section {
                    ForEach(group.clusters) { cluster in
                        ImportClusterRow(
                            cluster: cluster,
                            isSelected: coordinator.selectedClusterIDs.contains(cluster.id)
                        ) {
                            coordinator.toggleSelection(cluster)
                        }
                    }
                } header: {
                    HStack {
                        Text(String(group.year))
                            .font(LegacyFont.headline)
                            .foregroundStyle(LegacyColor.textPrimary)
                        Spacer()
                        Button(allSelectedInYear(group) ? "Deselect year" : "Select year") {
                            toggleYear(group)
                        }
                        .font(LegacyFont.caption)
                        .foregroundStyle(LegacyColor.accent)
                    }
                    .padding(.vertical, LegacySpacing.xxs)
                }
            }
        }
        .scrollContentBackground(.hidden)
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(coordinator.selectedClusterIDs.count == coordinator.clusters.count ? "Deselect all" : "Select all") {
                    if coordinator.selectedClusterIDs.count == coordinator.clusters.count {
                        coordinator.selectedClusterIDs = []
                    } else {
                        coordinator.selectedClusterIDs = Set(coordinator.clusters.map(\.id))
                    }
                }
                .font(LegacyFont.callout)
            }
        }
        #endif
    }

    // MARK: - Year grouping helpers

    private var clustersByYear: [(year: Int, clusters: [PhotoCluster])] {
        let grouped = Dictionary(grouping: coordinator.clusters) {
            Calendar.current.component(.year, from: $0.date)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (year: $0.key, clusters: $0.value.sorted { $0.date > $1.date }) }
    }

    private func allSelectedInYear(_ group: (year: Int, clusters: [PhotoCluster])) -> Bool {
        group.clusters.allSatisfy { coordinator.selectedClusterIDs.contains($0.id) }
    }

    private func toggleYear(_ group: (year: Int, clusters: [PhotoCluster])) {
        if allSelectedInYear(group) {
            group.clusters.forEach { coordinator.selectedClusterIDs.remove($0.id) }
        } else {
            group.clusters.forEach { coordinator.selectedClusterIDs.insert($0.id) }
        }
    }

    // MARK: - Completion / failure

    private func completionView(count: Int) -> some View {
        VStack(spacing: LegacySpacing.lg) {
            ContentUnavailableView(
                "Imported",
                systemImage: "checkmark.circle",
                description: Text("\(count) \(count == 1 ? "memory" : "memories") created. They appear in Memory Lane when processing finishes.")
            )
            Button("Import more") { coordinator.reset() }
                .buttonStyle(.legacySecondary)
        }
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: LegacySpacing.lg) {
            Text(message)
                .font(LegacyFont.callout)
                .foregroundStyle(LegacyColor.danger)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LegacySpacing.lg)
            #if os(iOS)
            // Permission failures can't be retried in-app — send the user to Settings.
            if message.localizedCaseInsensitiveContains("Settings") {
                OpenSettingsButton()
                    .padding(.horizontal, LegacySpacing.xl)
            } else {
                Button("Try again") {
                    Task { await coordinator.scanPhotoLibrary() }
                }
                .buttonStyle(.legacyPrimary)
            }
            #endif
            Button("Start over") { coordinator.reset() }
                .buttonStyle(.legacySecondary)
        }
    }
}

// MARK: - Cluster row

private struct ImportClusterRow: View {
    let cluster: PhotoCluster
    let isSelected: Bool
    let onToggle: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var placeName: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: LegacySpacing.md) {
                #if os(iOS)
                ClusterThumbnail(assetID: cluster.sampleIDs.first, side: 52, scale: displayScale)
                #endif

                VStack(alignment: .leading, spacing: LegacySpacing.xxs) {
                    // Lead with the place once we know it; fall back to the date so the
                    // row is never blank while geocoding is in flight.
                    Text(placeName ?? Self.dateFormatter.string(from: cluster.date))
                        .font(LegacyFont.headline)
                        .foregroundStyle(LegacyColor.textPrimary)
                        .lineLimit(1)
                    Text(secondaryLine)
                        .font(LegacyFont.caption)
                        .foregroundStyle(LegacyColor.textSecondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? LegacyColor.accent : LegacyColor.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .task(id: cluster.id) {
            #if os(iOS)
            guard placeName == nil else { return }
            placeName = await PlaceNameResolver.shared.placeName(
                lat: cluster.centroidLat,
                lng: cluster.centroidLng
            )
            #endif
        }
    }

    /// Photo count, prefixed with the date once the place name has claimed the lead line.
    private var secondaryLine: String {
        let photos = "\(cluster.photoCount) \(cluster.photoCount == 1 ? "photo" : "photos")"
        guard placeName != nil else { return photos }
        return "\(Self.dateFormatter.string(from: cluster.date)) · \(photos)"
    }
}

// MARK: - Cluster thumbnail

#if os(iOS)
private struct ClusterThumbnail: View {
    let assetID: String?
    let side: CGFloat
    let scale: CGFloat

    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: LegacyRadius.sm, style: .continuous)
            .fill(LegacyColor.textSecondary.opacity(0.12))
            .frame(width: side, height: side)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(LegacyColor.textSecondary.opacity(0.6))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.sm, style: .continuous))
            .task(id: assetID) {
                guard let assetID, image == nil else { return }
                image = await PHAssetThumbnailLoader.thumbnail(assetID: assetID, side: side, scale: scale)
            }
    }
}
#endif

// MARK: - Cluster map

#if os(iOS)
private struct ImportClusterMap: View {
    let clusters: [PhotoCluster]
    let selectedIDs: Set<String>

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            ForEach(clusters) { cluster in
                Annotation(
                    "\(cluster.photoCount)",
                    coordinate: CLLocationCoordinate2D(latitude: cluster.centroidLat, longitude: cluster.centroidLng)
                ) {
                    Circle()
                        .fill(selectedIDs.contains(cluster.id) ? LegacyColor.accent : LegacyColor.textSecondary.opacity(0.6))
                        .frame(width: markerSize(for: cluster), height: markerSize(for: cluster))
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onAppear { fitCamera() }
        .onChange(of: clusters.count) { _, _ in fitCamera() }
    }

    private func markerSize(for cluster: PhotoCluster) -> CGFloat {
        min(36, 12 + CGFloat(cluster.photoCount))
    }

    private func fitCamera() {
        guard !clusters.isEmpty else { return }
        let lats = clusters.map(\.centroidLat)
        let lngs = clusters.map(\.centroidLng)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (lats.max()! - lats.min()!) * 1.4 + 0.01),
            longitudeDelta: max(0.02, (lngs.max()! - lngs.min()!) * 1.4 + 0.01)
        )
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}
#endif
