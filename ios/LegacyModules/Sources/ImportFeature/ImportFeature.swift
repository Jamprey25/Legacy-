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
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .legacyFeatureBackground(glow: LegacyColor.accent)
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
            scanningView
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
            Spacer(minLength: LegacySpacing.xxxl)

            LegacyChromeCard(glow: LegacyColor.accent) {
                VStack(spacing: LegacySpacing.sm) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(LegacyColor.accent)
                    Text("Build your memory atlas")
                        .font(LegacyFont.title2)
                        .foregroundStyle(LegacyColor.textPrimary)
                    Text("We will scan your photo library for geotagged moments and group each visit into one memory.")
                        .font(LegacyFont.callout)
                        .foregroundStyle(LegacyColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, LegacySpacing.lg)
            #if os(iOS)
            Button("Start memory scan") {
                Task { await coordinator.scanPhotoLibrary() }
            }
            .buttonStyle(.legacyPrimary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LegacySpacing.lg)
            #endif

            Spacer(minLength: LegacySpacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Cluster explorer

    private var clusterExplorer: some View {
        VStack(spacing: 0) {
            LegacyChromeCard(glow: LegacyColor.accent) {
                HStack(spacing: LegacySpacing.md) {
                    VStack(alignment: .leading, spacing: LegacySpacing.xxs) {
                        Text("Memory Atlas")
                            .font(LegacyFont.headline)
                            .foregroundStyle(LegacyColor.textPrimary)
                        Text("\(coordinator.geoSampleCount) geotagged photos · \(coordinator.clusters.count) visits")
                            .font(LegacyFont.caption)
                            .foregroundStyle(LegacyColor.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(LegacyColor.accent)
                }
            }
            .padding(.horizontal, LegacySpacing.lg)
            .padding(.bottom, LegacySpacing.sm)

            if case .importing(let current, let total) = coordinator.phase {
                ProgressView(
                    "Saving \(current) of \(total) \(total == 1 ? "photo" : "photos")…",
                    value: Double(current),
                    total: Double(total)
                )
                .tint(LegacyColor.accent)
                .animation(.easeOut(duration: 0.25), value: current)
                .padding(.horizontal, LegacySpacing.lg)
                .padding(.top, LegacySpacing.sm)
            }

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

            #if os(iOS)
            ImportLocationBrowser(coordinator: coordinator)
            #endif

            if !coordinator.selectedClusterIDs.isEmpty {
                Button("Import \(coordinator.selectedClusterIDs.count) \(coordinator.selectedClusterIDs.count == 1 ? "memory" : "memories")") {
                    Task { await coordinator.importSelected() }
                }
                .buttonStyle(.legacyPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, LegacySpacing.lg)
                .padding(.vertical, LegacySpacing.sm)
                .disabled(coordinator.isImporting)
            }
        }
    }

    // MARK: - Completion / failure

    private func completionView(count: Int) -> some View {
        VStack(spacing: LegacySpacing.lg) {
            Spacer(minLength: LegacySpacing.xxxl)
            LegacyChromeCard {
                VStack(spacing: LegacySpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(LegacyColor.accent)
                    Text("Imported")
                        .font(LegacyFont.title2)
                        .foregroundStyle(LegacyColor.textPrimary)
                    Text("\(count) \(count == 1 ? "memory" : "memories") created. They appear in Memory Lane when processing finishes.")
                        .font(LegacyFont.callout)
                        .foregroundStyle(LegacyColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, LegacySpacing.lg)
            Button("Import more") { coordinator.reset() }
                .buttonStyle(.legacySecondary)
            Spacer(minLength: LegacySpacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: LegacySpacing.lg) {
            Spacer(minLength: LegacySpacing.xxxl)
            LegacyChromeCard(glow: LegacyColor.danger) {
                VStack(spacing: LegacySpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(LegacyColor.danger)
                    Text("Import interrupted")
                        .font(LegacyFont.title2)
                        .foregroundStyle(LegacyColor.textPrimary)
                    Text(message)
                        .font(LegacyFont.callout)
                        .foregroundStyle(LegacyColor.danger)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, LegacySpacing.lg)
            #if os(iOS)
            // Permission failures can't be retried in-app — send the user to Settings.
            if message.localizedCaseInsensitiveContains("Settings") {
                OpenSettingsButton()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, LegacySpacing.lg)
            } else {
                Button("Try again") {
                    Task { await coordinator.scanPhotoLibrary() }
                }
                .buttonStyle(.legacyPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, LegacySpacing.lg)
            }
            #endif
            Button("Start over") { coordinator.reset() }
                .buttonStyle(.legacySecondary)
            Spacer(minLength: LegacySpacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningView: some View {
        VStack(spacing: LegacySpacing.lg) {
            Spacer(minLength: LegacySpacing.xxxl)
            LegacyChromeCard(glow: LegacyColor.accent) {
                VStack(spacing: LegacySpacing.sm) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(LegacyColor.accent)
                    Text("Finding your memory places…")
                        .font(LegacyFont.title2)
                        .foregroundStyle(LegacyColor.textPrimary)
                    if let progress = coordinator.scanProgress {
                        ProgressView(value: Double(progress.scanned), total: Double(max(progress.total, 1)))
                            .tint(LegacyColor.accent)
                        Text("Scanning \(progress.scanned) of \(progress.total) — \(progress.found) geotagged")
                            .font(LegacyFont.caption)
                            .foregroundStyle(LegacyColor.textSecondary)
                    } else {
                        ProgressView()
                            .tint(LegacyColor.accent)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, LegacySpacing.lg)
            Spacer(minLength: LegacySpacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Cluster row

struct ImportClusterRow: View {
    let cluster: PhotoCluster
    let isSelected: Bool
    let placeName: String?
    let onToggle: () -> Void

    @Environment(\.displayScale) private var displayScale

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
