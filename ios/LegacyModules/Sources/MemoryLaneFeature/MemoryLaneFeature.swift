import APIClient
import DesignSystem
import LocationEngine
import SwiftUI

/// Grid of own memories — oldest first, no proximity check for owner content.
public enum MemoryLaneFeature {
    public static let version = "0.1.0"
}

#if os(iOS)
import MapKit
#endif

@MainActor
@Observable
public final class MemoryLaneCoordinator {
    public init(apiClient: LegacyAPIClient, locationEngine: LocationEngine) {
        self.apiClient = apiClient
        self.locationEngine = locationEngine
    }

    private let apiClient: LegacyAPIClient
    private let locationEngine: LocationEngine
    private var nextCursor: String?

    public var sort: MemorySort = .oldest
    public var mediaTypeFilter: MemoryMediaTypeFilter = .all

    public private(set) var items: [MemoryLaneItem] = []
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var errorMessage: String?

    public private(set) var detail: MemoryDetail?
    public private(set) var isLoadingDetail = false
    public private(set) var isUnlocking = false
    public private(set) var ownerMediaURL: URL?
    public private(set) var unlockedMediaURL: URL?
    public private(set) var unlockMessage: String?

    public var canLoadMore: Bool { nextCursor != nil }

    /// Memories dropped on today's calendar day in previous years — surfaced as a
    /// resurfacing banner. Most-recent year first. Empty on days with no match.
    public var onThisDayItems: [MemoryLaneItem] {
        items
            .filter { MemoryLaneFormatting.isOnThisDay(dropDate: $0.dropDate) }
            .sorted { $0.dropDate > $1.dropDate }
    }

    public func setSort(_ newSort: MemorySort) async {
        guard newSort != sort else { return }
        sort = newSort
        await loadInitial()
    }

    public func setMediaTypeFilter(_ filter: MemoryMediaTypeFilter) async {
        guard filter != mediaTypeFilter else { return }
        mediaTypeFilter = filter
        await loadInitial()
    }

    public func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            items = try await fetchAllPages()
            nextCursor = nil
        } catch {
            errorMessage = "Could not load your memories."
        }
    }

    private func fetchAllPages() async throws -> [MemoryLaneItem] {
        var aggregated: [MemoryLaneItem] = []
        var cursor: String?
        repeat {
            let response = try await apiClient.listMemories(
                cursor: cursor,
                sort: sort,
                mediaType: mediaTypeFilter
            )
            aggregated.append(contentsOf: response.memories)
            cursor = response.nextCursor
        } while cursor != nil
        return aggregated
    }

    public func loadMoreIfNeeded(current item: MemoryLaneItem) async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        guard item.id == items.last?.id else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let response = try await apiClient.listMemories(
                cursor: cursor,
                sort: sort,
                mediaType: mediaTypeFilter
            )
            items.append(contentsOf: response.memories)
            nextCursor = response.nextCursor
        } catch {
            errorMessage = "Could not load more memories."
        }
    }

    public func loadDetail(for item: MemoryLaneItem) async {
        isLoadingDetail = true
        detail = nil
        ownerMediaURL = nil
        unlockedMediaURL = nil
        unlockMessage = nil
        defer { isLoadingDetail = false }

        if item.scanStatus == "clear",
           let urlString = item.previewImageURL,
           let url = URL(string: urlString) {
            ownerMediaURL = url
        }

        do {
            let loaded = try await apiClient.getMemory(id: item.memoryID)
            detail = loaded
            if loaded.scanStatus == "clear", let urlString = loaded.mediaURL ?? loaded.thumbnailURL,
               let url = URL(string: urlString) {
                ownerMediaURL = url
            }
        } catch {
            errorMessage = "Could not load memory details."
        }
    }

    /// Opens media when physically at the drop point (uses unlock — no dwell for own memories).
    public func openAtLocation(memoryID: String) async {
        isUnlocking = true
        unlockMessage = nil
        unlockedMediaURL = nil
        defer { isUnlocking = false }

        do {
            let fix = try await locationEngine.acquireFix()
            let attestation = await AppAttestBridge.currentAssertionBase64()
            let body = LocationRequest(
                lat: fix.lat,
                lng: fix.lng,
                accuracyM: fix.accuracyM,
                attestation: attestation
            )
            let response = try await apiClient.unlock(memoryID: memoryID, body)
            if let urlString = response.media.first?.url, let url = URL(string: urlString) {
                unlockedMediaURL = url
            }
            unlockMessage = response.caption
        } catch let LegacyAPIError.locked(code, message, _) {
            unlockMessage = code == "not_in_range"
                ? "Visit the drop location to view this memory."
                : message
        } catch {
            unlockMessage = "Could not open memory. Try again when you have a signal."
        }
    }
}

public struct MemoryLaneFeatureRootView: View {
    public init(coordinator: MemoryLaneCoordinator) {
        self.coordinator = coordinator
    }

    @Bindable private var coordinator: MemoryLaneCoordinator

    private let columns = [
        GridItem(.flexible(), spacing: LegacySpacing.md),
        GridItem(.flexible(), spacing: LegacySpacing.md),
    ]

    public var body: some View {
        NavigationStack {
            Group {
                if coordinator.isLoading && coordinator.items.isEmpty {
                    ProgressView()
                        .tint(LegacyColor.accent)
                } else if coordinator.items.isEmpty {
                    ContentUnavailableView(
                        "Memory Lane",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text(emptyDescription)
                    )
                } else {
                    ScrollView {
                        #if os(iOS)
                        if !coordinator.onThisDayItems.isEmpty {
                            OnThisDaySection(items: coordinator.onThisDayItems)
                        }
                        #endif

                        LazyVGrid(columns: columns, spacing: LegacySpacing.md) {
                            ForEach(coordinator.items) { item in
                                NavigationLink(value: item) {
                                    MemoryLaneCard(item: item)
                                }
                                .buttonStyle(.plain)
                                .onAppear {
                                    Task { await coordinator.loadMoreIfNeeded(current: item) }
                                }
                            }
                        }
                        .padding(LegacySpacing.lg)

                        if coordinator.isLoadingMore {
                            ProgressView()
                                .tint(LegacyColor.accent)
                                .padding(.bottom, LegacySpacing.lg)
                        }

                        if coordinator.items.count > 1 {
                            Text("\(coordinator.items.count) memories")
                                .font(LegacyFont.caption)
                                .foregroundStyle(LegacyColor.textSecondary)
                                .padding(.bottom, LegacySpacing.lg)
                        }
                    }
                }
            }
            .background(LegacyColor.background)
            .navigationTitle("Memory Lane")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    MemoryLaneFilterMenu(coordinator: coordinator)
                }
            }
            .navigationDestination(for: MemoryLaneItem.self) { item in
                MemoryLaneDetailView(item: item, coordinator: coordinator)
            }
            #endif
            .task { await coordinator.loadInitial() }
            .refreshable { await coordinator.loadInitial() }
            .safeAreaInset(edge: .bottom) {
                if let message = coordinator.errorMessage {
                    Text(message)
                        .font(LegacyFont.caption)
                        .foregroundStyle(LegacyColor.danger)
                        .padding(LegacySpacing.md)
                        .frame(maxWidth: .infinity)
                        .background(LegacyColor.background)
                }
            }
        }
    }

    private var emptyDescription: String {
        if coordinator.mediaTypeFilter != .all {
            return "No \(coordinator.mediaTypeFilter.label.lowercased()) match this filter."
        }
        return coordinator.sort == .newest
            ? "Memories you drop will appear here, newest first."
            : "Memories you drop will appear here, oldest first."
    }
}

#if os(iOS)
private struct MemoryLaneFilterMenu: View {
    @Bindable var coordinator: MemoryLaneCoordinator

    var body: some View {
        Menu {
            Section("Sort") {
                ForEach(MemorySort.allCases, id: \.self) { order in
                    Button {
                        Task { await coordinator.setSort(order) }
                    } label: {
                        if coordinator.sort == order {
                            Label(order.label, systemImage: "checkmark")
                        } else {
                            Text(order.label)
                        }
                    }
                }
            }
            Section("Type") {
                ForEach(MemoryMediaTypeFilter.allCases, id: \.self) { filter in
                    Button {
                        Task { await coordinator.setMediaTypeFilter(filter) }
                    } label: {
                        if coordinator.mediaTypeFilter == filter {
                            Label(filter.label, systemImage: "checkmark")
                        } else {
                            Text(filter.label)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Sort and filter memories")
    }
}
#endif

#if os(iOS)
/// "On this day" resurfacing strip — a horizontal carousel of memories from
/// today's date in previous years. Taps open the same detail destination.
private struct OnThisDaySection: View {
    let items: [MemoryLaneItem]

    var body: some View {
        VStack(alignment: .leading, spacing: LegacySpacing.sm) {
            HStack(spacing: LegacySpacing.xs) {
                Image(systemName: "sparkles")
                    .foregroundStyle(LegacyColor.accent)
                Text("On this day")
                    .font(LegacyFont.headline)
                    .foregroundStyle(LegacyColor.textPrimary)
            }
            .padding(.horizontal, LegacySpacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LegacySpacing.md) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            OnThisDayCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, LegacySpacing.lg)
            }
        }
        .padding(.top, LegacySpacing.md)
        .padding(.bottom, LegacySpacing.xs)
    }
}

private struct OnThisDayCard: View {
    let item: MemoryLaneItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: LegacyRadius.md)
                .fill(LegacyColor.surface)
                .frame(width: 160, height: 160)

            if let urlString = item.previewImageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholderIcon
                    default:
                        ProgressView().tint(LegacyColor.accent)
                    }
                }
                .frame(width: 160, height: 160)
                .clipped()
            } else {
                placeholderIcon
                    .frame(width: 160, height: 160)
            }

            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.65)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(MemoryLaneFormatting.yearsAgoToday(dropDate: item.dropDate))
                .font(LegacyFont.caption)
                .foregroundStyle(.white)
                .padding(LegacySpacing.sm)
        }
        .frame(width: 160, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: LegacyRadius.md)
                .stroke(LegacyColor.accent.opacity(0.4), lineWidth: 1)
        )
    }

    private var placeholderIcon: some View {
        Image(systemName: item.mediaType == "text" ? "text.quote" : "photo")
            .font(.title)
            .foregroundStyle(LegacyColor.textSecondary)
    }
}
#endif

private struct MemoryLaneCard: View {
    let item: MemoryLaneItem

    var body: some View {
        VStack(alignment: .leading, spacing: LegacySpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: LegacyRadius.sm)
                    .fill(LegacyColor.surface)
                    .aspectRatio(1, contentMode: .fit)

                if let urlString = item.previewImageURL,
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(LegacyColor.textSecondary)
                        default:
                            ProgressView().tint(LegacyColor.accent)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.sm))
                } else {
                    Image(systemName: item.mediaType == "text" ? "text.quote" : "photo")
                        .font(.title2)
                        .foregroundStyle(LegacyColor.textSecondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.sm))

            if let label = item.displayLabel {
                Text(label)
                    .font(LegacyFont.caption)
                    .foregroundStyle(LegacyColor.textPrimary)
                    .lineLimit(2)
            }

            Text(item.dropDate)
                .font(LegacyFont.caption)
                .foregroundStyle(LegacyColor.textPrimary)

            Text(MemoryLaneFormatting.timeSinceDrop(createdAtISO: item.createdAt))
                .font(LegacyFont.metric)
                .foregroundStyle(LegacyColor.accent)

            if item.scanStatus == "pending" {
                Text("Uploading…")
                    .font(LegacyFont.caption)
                    .foregroundStyle(LegacyColor.textSecondary)
            }
        }
    }
}

#if os(iOS)
struct MemoryLaneDetailView: View {
    let item: MemoryLaneItem
    @Bindable var coordinator: MemoryLaneCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LegacySpacing.lg) {
                if coordinator.isLoadingDetail {
                    ProgressView()
                        .tint(LegacyColor.accent)
                        .frame(maxWidth: .infinity)
                } else if let detail = coordinator.detail {
                    if detail.mediaType != "text" {
                        DropLocationMap(lat: detail.lat, lng: detail.lng)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md))
                    }

                    LabeledContent("Dropped") {
                        Text(detail.createdAt.prefix(10))
                            .font(LegacyFont.body)
                    }
                    LabeledContent("Status") {
                        Text(detail.scanStatus)
                            .font(LegacyFont.body)
                    }

                    if detail.scanStatus == "clear" {
                        if coordinator.ownerMediaURL == nil && coordinator.unlockedMediaURL == nil,
                           item.previewImageURL == nil {
                            Button("Open at location") {
                                Task { await coordinator.openAtLocation(memoryID: detail.memoryID) }
                            }
                            .buttonStyle(.legacyPrimary)
                            .disabled(coordinator.isUnlocking)
                        }
                    }

                    if coordinator.isUnlocking {
                        ProgressView()
                            .tint(LegacyColor.accent)
                    }

                    if let url = coordinator.unlockedMediaURL ?? coordinator.ownerMediaURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md))
                            case .failure:
                                Text("Could not load photo")
                                    .foregroundStyle(LegacyColor.textSecondary)
                            default:
                                ProgressView()
                            }
                        }
                    }

                    if let message = coordinator.unlockMessage {
                        Text(message)
                            .font(LegacyFont.callout)
                            .foregroundStyle(LegacyColor.textSecondary)
                    }
                }
            }
            .padding(LegacySpacing.lg)
        }
        .background(LegacyColor.background)
        .navigationTitle(item.dropDate)
        .navigationBarTitleDisplayMode(.inline)
        .task { await coordinator.loadDetail(for: item) }
    }
}

private struct DropLocationMap: View {
    let lat: Double
    let lng: Double

    @State private var position: MapCameraPosition

    init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        )
        _position = State(initialValue: .region(region))
    }

    var body: some View {
        Map(position: $position) {
            Marker("Drop point", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
        .mapStyle(.standard(elevation: .realistic))
        .allowsHitTesting(false)
    }
}
#endif
