#if os(iOS)
import APIClient
import DesignSystem
import MapKit
import SwiftUI

enum MemoryLaneViewMode: String, CaseIterable, Identifiable {
    case grid
    case places
    case map

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grid: return "Grid"
        case .places: return "Places"
        case .map: return "Map"
        }
    }

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .places: return "mappin.and.ellipse"
        case .map: return "map"
        }
    }
}

struct MemoryPlacesAtlasView: View {
    let clusters: [MemoryPlaceCluster]
    let onSelect: (MemoryPlaceCluster) -> Void

    var body: some View {
        LazyVStack(spacing: LegacySpacing.sm) {
            ForEach(clusters) { cluster in
                Button { onSelect(cluster) } label: {
                    HStack(spacing: LegacySpacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: LegacyRadius.sm, style: .continuous)
                                .fill(LegacyColor.accent.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(LegacyColor.accent)
                        }
                        VStack(alignment: .leading, spacing: LegacySpacing.xxs) {
                            Text(cluster.title)
                                .font(LegacyFont.headline)
                                .foregroundStyle(LegacyColor.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text("\(cluster.items.count) \(cluster.items.count == 1 ? "memory" : "memories")")
                                .font(LegacyFont.caption)
                                .foregroundStyle(LegacyColor.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LegacyColor.textSecondary.opacity(0.6))
                    }
                    .padding(LegacySpacing.md)
                    .background(LegacyColor.surface.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(cluster.title), \(cluster.items.count) memories")
            }
        }
        .padding(.horizontal, LegacySpacing.lg)
    }
}

struct MemoryPlacesMapView: View {
    let clusters: [MemoryPlaceCluster]
    let onSelect: (MemoryPlaceCluster) -> Void

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            ForEach(clusters) { cluster in
                Annotation(cluster.title, coordinate: CLLocationCoordinate2D(latitude: cluster.lat, longitude: cluster.lng)) {
                    Button {
                        onSelect(cluster)
                    } label: {
                        Text("\(cluster.items.count)")
                            .font(LegacyFont.caption)
                            .foregroundStyle(LegacyColor.textOnAccent)
                            .padding(8)
                            .background(LegacyColor.accent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md))
        .padding(.horizontal, LegacySpacing.lg)
        .onAppear {
            fitCamera()
        }
        .onChange(of: clusters.count) { _, _ in fitCamera() }
    }

    private func fitCamera() {
        guard !clusters.isEmpty else { return }
        if clusters.count == 1, let c = clusters.first {
            position = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))
            return
        }
        var rect = MKMapRect.null
        for cluster in clusters {
            let point = MKMapPoint(CLLocationCoordinate2D(latitude: cluster.lat, longitude: cluster.lng))
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        position = .rect(rect.insetBy(dx: -rect.size.width * 0.3, dy: -rect.size.height * 0.3))
    }
}

struct MemoryLaneSearchBar: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: LegacySpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(LegacyColor.textSecondary)
            TextField("Search memories", text: $query)
                .font(LegacyFont.body)
                .foregroundStyle(LegacyColor.textPrimary)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LegacyColor.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(LegacySpacing.md)
        .background(LegacyColor.surface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md, style: .continuous))
    }
}

struct MemoryPlaceFilterSheet: View {
    let cluster: MemoryPlaceCluster
    @Bindable var coordinator: MemoryLaneCoordinator
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: LegacySpacing.md),
        GridItem(.flexible(), spacing: LegacySpacing.md),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: LegacySpacing.md) {
                    ForEach(cluster.items) { item in
                        NavigationLink(value: item) {
                            MemoryLaneCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(LegacySpacing.lg)
            }
            .background(LegacyColor.background)
            .navigationTitle(cluster.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: MemoryLaneItem.self) { item in
                MemoryLaneDetailView(item: item, coordinator: coordinator)
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
