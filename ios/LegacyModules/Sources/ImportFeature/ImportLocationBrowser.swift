import APIClient
import DesignSystem
import SwiftUI

#if os(iOS)

/// Country → State → City → visits drill-down for choosing what to import. Selection is by
/// cluster ID (shared with the coordinator), so a checkmark at any level toggles every visit
/// beneath it, and individual visits stay selectable at the leaf. Replaces the flat list,
/// which was overwhelming for large libraries.
struct ImportLocationBrowser: View {
    @Bindable var coordinator: ImportCoordinator

    var body: some View {
        ImportRegionLevel(
            coordinator: coordinator,
            title: "Import",
            depth: 0,
            clusters: coordinator.clusters
        )
    }
}

/// One screen of the drill-down. `depth` selects which part of the region groups the rows:
/// 0 = country, 1 = state/admin, 2 = city, 3 = individual visits (leaf).
struct ImportRegionLevel: View {
    @Bindable var coordinator: ImportCoordinator
    let title: String
    let depth: Int
    let clusters: [PhotoCluster]

    private var isLeaf: Bool { depth >= 3 }

    var body: some View {
        List {
            if depth == 0, coordinator.isResolvingRegions {
                Section {
                    HStack(spacing: LegacySpacing.sm) {
                        ProgressView().tint(LegacyColor.accent)
                        Text("Sorting \(coordinator.clusters.count) visits by location…")
                            .font(LegacyFont.caption)
                            .foregroundStyle(LegacyColor.textSecondary)
                    }
                }
            }

            if isLeaf {
                ForEach(sortedVisits) { cluster in
                    ImportClusterRow(
                        cluster: cluster,
                        isSelected: coordinator.selectedClusterIDs.contains(cluster.id),
                        placeName: coordinator.placeName(for: cluster.id)
                    ) {
                        coordinator.toggleSelection(cluster)
                    }
                    .task(id: cluster.id) {
                        await coordinator.resolveRegions(for: [cluster.id])
                    }
                }
            } else {
                ForEach(groups) { group in
                    ImportGroupRow(
                        group: group,
                        selectedIDs: coordinator.selectedClusterIDs,
                        onToggleAll: { toggleAll(group.clusters) },
                        destination: {
                            ImportRegionLevel(
                                coordinator: coordinator,
                                title: group.name,
                                depth: depth + 1,
                                clusters: group.clusters
                            )
                        }
                    )
                    .task(id: group.id) {
                        await coordinator.resolveRegions(for: group.clusters.map(\.id))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(depth == 0 ? "Import" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(allSelected ? "Deselect all" : "Select all") {
                    toggleAll(clusters)
                }
                .font(LegacyFont.callout)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if depth > 0, !coordinator.selectedClusterIDs.isEmpty {
                let count = coordinator.selectedClusterIDs.count
                Button("Import \(count) \(count == 1 ? "memory" : "memories")") {
                    Task { await coordinator.importSelected() }
                }
                .buttonStyle(.legacyPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, LegacySpacing.lg)
                .padding(.vertical, LegacySpacing.sm)
                .background(LegacyColor.background.opacity(0.96))
                .disabled(coordinator.isImporting)
            }
        }
    }

    // MARK: - Grouping

    private var sortedVisits: [PhotoCluster] {
        clusters.sorted { $0.date > $1.date }
    }

    private var groups: [RegionGroup] {
        Dictionary(grouping: clusters) { Self.groupName(coordinator.clusterRegions[$0.id], depth: depth) }
            .map { RegionGroup(name: $0.key, clusters: $0.value) }
            .sorted(by: Self.order)
    }

    /// Alphabetical, but keep "Locating…" / catch-all buckets at the bottom.
    private static func order(_ a: RegionGroup, _ b: RegionGroup) -> Bool {
        let trailing: Set<String> = ["Locating…", "Unknown location", "Other"]
        let aTrail = trailing.contains(a.name)
        let bTrail = trailing.contains(b.name)
        if aTrail != bTrail { return !aTrail }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    private static func groupName(_ region: ImportRegion?, depth: Int) -> String {
        guard let region else { return "Locating…" }
        switch depth {
        case 0: return region.country.isEmpty ? "Unknown location" : region.country
        case 1: return region.admin.isEmpty ? "Other" : region.admin
        default: return region.city.isEmpty ? "Other" : region.city
        }
    }

    // MARK: - Selection

    private var allSelected: Bool {
        !clusters.isEmpty && clusters.allSatisfy { coordinator.selectedClusterIDs.contains($0.id) }
    }

    private func toggleAll(_ subset: [PhotoCluster]) {
        let ids = subset.map(\.id)
        if ids.allSatisfy({ coordinator.selectedClusterIDs.contains($0) }) {
            coordinator.deselectClusters(ids)
        } else {
            coordinator.selectClusters(ids)
        }
    }
}

private struct RegionGroup: Identifiable {
    let name: String
    let clusters: [PhotoCluster]
    var id: String { name }
}

/// A grouping row: a leading select-all checkmark (toggles every visit beneath it) plus a
/// tappable area that drills one level deeper. The checkmark is a borderless button so its
/// taps don't trigger the navigation.
private struct ImportGroupRow<Destination: View>: View {
    let group: RegionGroup
    let selectedIDs: Set<String>
    let onToggleAll: () -> Void
    @ViewBuilder let destination: () -> Destination

    private var photoCount: Int { group.clusters.reduce(0) { $0 + $1.photoCount } }
    private var selectedCount: Int { group.clusters.filter { selectedIDs.contains($0.id) }.count }

    private var selection: GroupSelection {
        if selectedCount == 0 { return .none }
        return selectedCount == group.clusters.count ? .all : .partial
    }

    var body: some View {
        HStack(spacing: LegacySpacing.md) {
            Button(action: onToggleAll) {
                Image(systemName: selection.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(selection == .none ? LegacyColor.textSecondary : LegacyColor.accent)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(selection == .all ? "Deselect \(group.name)" : "Select all in \(group.name)")

            NavigationLink(destination: destination()) {
                HStack {
                    VStack(alignment: .leading, spacing: LegacySpacing.xxs) {
                        Text(group.name)
                            .font(LegacyFont.headline)
                            .foregroundStyle(LegacyColor.textPrimary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(LegacyFont.caption)
                            .foregroundStyle(LegacyColor.textSecondary)
                    }
                    Spacer()
                    if selectedCount > 0 {
                        Text("\(selectedCount)")
                            .font(LegacyFont.caption.weight(.semibold))
                            .foregroundStyle(LegacyColor.accent)
                    }
                }
            }
        }
    }

    private var subtitle: String {
        let visits = "\(group.clusters.count) \(group.clusters.count == 1 ? "visit" : "visits")"
        let photos = "\(photoCount) \(photoCount == 1 ? "photo" : "photos")"
        return "\(visits) · \(photos)"
    }
}

private enum GroupSelection {
    case none, partial, all

    var icon: String {
        switch self {
        case .none: "circle"
        case .partial: "minus.circle.fill"
        case .all: "checkmark.circle.fill"
        }
    }
}

#endif
