import APIClient
import DesignSystem
import LocationEngine
import SwiftUI

/// Grid of own memories — oldest first, no proximity check for owner content.
public enum MemoryLaneFeature {
    public static let version = "0.1.0"
}

/// A year-bucket of memories for sectioned browsing. `year == 0` means the drop
/// date could not be parsed and is presented as "Undated".
public struct MemorySection: Identifiable, Equatable {
    public let year: Int
    public let items: [MemoryLaneItem]
    public var id: Int { year }

    public var title: String { year == 0 ? "Undated" : String(year) }
}

#if os(iOS)
import MapKit
import CoreLocation
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
    public var searchQuery: String = ""
    #if os(iOS)
    public var viewMode: MemoryLaneViewMode = .grid
    public var selectedPlaceCluster: MemoryPlaceCluster?
    #endif
    /// Memory IDs to highlight after import — cleared when user opens one.
    public var highlightedMemoryIDs: Set<String> = []

    public private(set) var items: [MemoryLaneItem] = []
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var errorMessage: String?

    public private(set) var detail: MemoryDetail?
    public private(set) var isLoadingDetail = false
    public private(set) var isDeletingDetail = false
    public private(set) var isUnlocking = false
    public private(set) var ownerMediaURL: URL?
    public private(set) var unlockedMediaURL: URL?
    public private(set) var unlockMessage: String?
    public private(set) var detailReturnCount: Int?
    public private(set) var detailLastFoundAt: String?

    public var canLoadMore: Bool { nextCursor != nil }

    /// Memories dropped on today's calendar day in previous years — surfaced as a
    /// resurfacing banner. Uses ±3 day window when exact-day matches are empty.
    public var onThisDayItems: [MemoryLaneItem] {
        let exact = items.filter { MemoryLaneFormatting.isOnThisDay(dropDate: $0.dropDate) }
        let pool = exact.isEmpty
            ? items.filter { MemoryLaneFormatting.isOnThisDayWindow(dropDate: $0.dropDate, windowDays: 3) }
            : exact
        return pool.sorted { $0.dropDate > $1.dropDate }
    }

    public var filteredItems: [MemoryLaneItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { item in
            if item.dropDate.lowercased().contains(q) { return true }
            if let label = item.displayLabel?.lowercased(), label.contains(q) { return true }
            if item.mediaType.lowercased().contains(q) { return true }
            if let year = MemoryLaneFormatting.year(of: item.dropDate), String(year).contains(q) { return true }
            #if os(iOS)
            if let cluster = placeClusters.first(where: { $0.items.contains(where: { $0.memoryID == item.memoryID }) }),
               let name = cluster.placeName?.lowercased(), name.contains(q) {
                return true
            }
            #endif
            return false
        }
    }

    public var placeClusters: [MemoryPlaceCluster] {
        let cache = UserDefaults.standard.dictionary(forKey: "legacyPlaceNameCache") as? [String: String] ?? [:]
        return MemoryPlaceClustering.cluster(items: filteredItems).map { cluster in
            MemoryPlaceCluster(
                id: cluster.id,
                lat: cluster.lat,
                lng: cluster.lng,
                items: cluster.items,
                placeName: cache[cluster.id]
            )
        }
    }

    public var uniquePlaceCount: Int { placeClusters.count }

    public var statsLabel: String {
        "\(uniquePlaceCount) \(uniquePlaceCount == 1 ? "place" : "places") · \(items.count) \(items.count == 1 ? "memory" : "memories")"
    }

    /// Items grouped into year sections for browsing. Section order follows the
    /// active sort (newest → years descending). Within a year, the backend's
    /// ordering is preserved. Unparseable dates collect under year 0 ("Undated").
    public var sections: [MemorySection] {
        let source = filteredItems
        let grouped = Dictionary(grouping: source) { MemoryLaneFormatting.year(of: $0.dropDate) ?? 0 }
        let unsorted = grouped.map { MemorySection(year: $0.key, items: $0.value) }
        return unsorted.sorted { sort == .newest ? $0.year > $1.year : $0.year < $1.year }
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
            #if os(iOS)
            await resolvePlaceNames()
            OnThisDayNotificationScheduler.reschedule(with: items)
            updateWidgetDefaults()
            #endif
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

    #if os(iOS)
    public func resolvePlaceNames() async {
        let clusters = MemoryPlaceClustering.cluster(items: items)
        var named: [String: String] = [:]
        for cluster in clusters {
            let location = CLLocation(latitude: cluster.lat, longitude: cluster.lng)
            if let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location),
               let placemark = placemarks.first {
                let primary = placemark.areasOfInterest?.first
                    ?? placemark.subLocality
                    ?? placemark.locality
                    ?? placemark.name
                if let primary {
                    let label: String
                    if let city = placemark.locality, city != primary {
                        label = "\(primary), \(city)"
                    } else {
                        label = primary
                    }
                    named[cluster.id] = label
                }
            }
        }
        UserDefaults.standard.set(named, forKey: "legacyPlaceNameCache")
    }

    public func placeName(for item: MemoryLaneItem) -> String? {
        guard let lat = item.lat, let lng = item.lng else { return nil }
        let key = MemoryPlaceClustering.bucketKey(lat: lat, lng: lng)
        let cache = UserDefaults.standard.dictionary(forKey: "legacyPlaceNameCache") as? [String: String]
        return cache?[key]
    }

    public func highlightImportedMemories(_ memoryIDs: [String]) {
        highlightedMemoryIDs = Set(memoryIDs)
    }

    public func clearHighlight(for memoryID: String) {
        highlightedMemoryIDs.remove(memoryID)
    }

    private func updateWidgetDefaults() {
        guard let defaults = UserDefaults(suiteName: "group.app.legacy.shared") else { return }
        let matches = onThisDayItems
        if let first = matches.first {
            defaults.set("On this day", forKey: "widget.onThisDay.title")
            defaults.set(MemoryLaneFormatting.onThisDayLabel(dropDate: first.dropDate), forKey: "widget.onThisDay.subtitle")
        } else {
            defaults.set("On this day", forKey: "widget.onThisDay.title")
            defaults.set("Open Legacy to browse your map", forKey: "widget.onThisDay.subtitle")
        }
    }
    #endif

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
        detailReturnCount = nil
        detailLastFoundAt = nil
        defer { isLoadingDetail = false }

        if item.scanStatus == "clear",
           let urlString = item.previewImageURL,
           let url = URL(string: urlString) {
            ownerMediaURL = url
        }

        do {
            let loaded = try await apiClient.getMemory(id: item.memoryID)
            detail = loaded
            detailReturnCount = loaded.returnCount
            detailLastFoundAt = loaded.lastFoundAt
            if loaded.scanStatus == "clear", let urlString = loaded.mediaURL ?? loaded.thumbnailURL,
               let url = URL(string: urlString) {
                ownerMediaURL = url
            }
            await pollLifecycleStatus(for: item.memoryID, initial: loaded)
        } catch {
            errorMessage = "Could not load memory details."
        }
    }

    private func shouldPollLifecycle(_ memory: MemoryDetail) -> Bool {
        if let uploadStatus = memory.uploadStatus {
            return !uploadStatus.isReady
        }
        return memory.scanStatus != "clear"
    }

    private func pollLifecycleStatus(for memoryID: String, initial: MemoryDetail) async {
        guard shouldPollLifecycle(initial) else { return }
        for _ in 0..<8 {
            if Task.isCancelled { return }
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            do {
                let refreshed = try await apiClient.getMemory(id: memoryID)
                detail = refreshed
                if refreshed.scanStatus == "clear",
                   let urlString = refreshed.mediaURL ?? refreshed.thumbnailURL,
                   let url = URL(string: urlString) {
                    ownerMediaURL = url
                }
                if !shouldPollLifecycle(refreshed) { return }
            } catch {
                // Keep current detail state if refresh fails; user can pull-to-refresh/reopen.
                return
            }
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
            detailReturnCount = response.returnCount
            LegacyHaptics.unlockCeremony(isFirstReturn: response.returnCount <= 1)
            if let refreshed = try? await apiClient.getMemory(id: memoryID) {
                detail = refreshed
                detailReturnCount = refreshed.returnCount
                detailLastFoundAt = refreshed.lastFoundAt
            }
        } catch let LegacyAPIError.locked(code, message, _) {
            unlockMessage = code == "not_in_range"
                ? "Visit the drop location to view this memory."
                : message
        } catch let error as LegacyAPIError where error.isAppAttestFailure {
            unlockMessage = "Device attestation failed. Reopen Legacy and try again on a real device."
        } catch LegacyAPIError.unauthorized {
            unlockMessage = "Session expired. Sign out and sign in again."
        } catch {
            unlockMessage = "Could not open memory. Try again when you have a signal."
        }
    }

    @discardableResult
    public func deleteMemory(memoryID: String) async -> Bool {
        guard !isDeletingDetail else { return false }
        isDeletingDetail = true
        defer { isDeletingDetail = false }

        do {
            try await apiClient.deleteMemory(id: memoryID)
            items.removeAll { $0.memoryID == memoryID }
            detail = nil
            ownerMediaURL = nil
            unlockedMediaURL = nil
            unlockMessage = nil
            return true
        } catch LegacyAPIError.notFound {
            errorMessage = "Memory no longer exists."
            return false
        } catch {
            errorMessage = "Could not remove memory. Try again."
            return false
        }
    }
}

public struct MemoryLaneFeatureRootView: View {
    public init(
        coordinator: MemoryLaneCoordinator,
        onStartDropping: (() -> Void)? = nil,
        onStartImporting: (() -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.onStartDropping = onStartDropping
        self.onStartImporting = onStartImporting
    }

    @Bindable private var coordinator: MemoryLaneCoordinator
    private let onStartDropping: (() -> Void)?
    private let onStartImporting: (() -> Void)?

    private let columns = [
        GridItem(.flexible(), spacing: LegacySpacing.md),
        GridItem(.flexible(), spacing: LegacySpacing.md),
    ]

    public var body: some View {
        NavigationStack {
            Group {
                if coordinator.isLoading && coordinator.items.isEmpty {
                    MemoryLaneSkeletonGallery(columns: columns)
                } else if coordinator.items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LegacyChromeCard(glow: Color(red: 0.80, green: 0.62, blue: 0.95)) {
                            HStack(spacing: LegacySpacing.md) {
                                VStack(alignment: .leading, spacing: LegacySpacing.xxs) {
                                    Text("Memory Vault")
                                        .font(LegacyFont.headline)
                                        .foregroundStyle(LegacyColor.textPrimary)
                                    Text(coordinator.statsLabel)
                                        .font(LegacyFont.caption)
                                        .foregroundStyle(LegacyColor.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(LegacyColor.accent)
                            }
                        }
                        .padding(.horizontal, LegacySpacing.lg)
                        .padding(.top, LegacySpacing.sm)

                        #if os(iOS)
                        Picker("View", selection: $coordinator.viewMode) {
                            ForEach(MemoryLaneViewMode.allCases) { mode in
                                Label(mode.label, systemImage: mode.icon).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, LegacySpacing.lg)
                        .padding(.top, LegacySpacing.sm)

                        MemoryLaneSearchBar(query: $coordinator.searchQuery)
                            .padding(.horizontal, LegacySpacing.lg)
                            .padding(.top, LegacySpacing.sm)

                        if !coordinator.onThisDayItems.isEmpty {
                            OnThisDaySection(items: coordinator.onThisDayItems)
                        }

                        switch coordinator.viewMode {
                        case .grid:
                            gridContent
                        case .places:
                            MemoryPlacesAtlasView(clusters: coordinator.placeClusters) { cluster in
                                coordinator.selectedPlaceCluster = cluster
                            }
                            .padding(.vertical, LegacySpacing.md)
                        case .map:
                            MemoryPlacesMapView(clusters: coordinator.placeClusters) { cluster in
                                coordinator.selectedPlaceCluster = cluster
                            }
                            .padding(.vertical, LegacySpacing.md)
                        }
                        #else
                        gridContent
                        #endif
                    }
                }
            }
            .legacyFeatureBackground(glow: Color(red: 0.80, green: 0.62, blue: 0.95))
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
                    .onAppear { coordinator.clearHighlight(for: item.memoryID) }
            }
            .sheet(item: $coordinator.selectedPlaceCluster) { cluster in
                MemoryPlaceFilterSheet(cluster: cluster, coordinator: coordinator)
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

    @ViewBuilder
    private var gridContent: some View {
        LazyVStack(alignment: .leading, spacing: LegacySpacing.lg, pinnedViews: [.sectionHeaders]) {
            ForEach(coordinator.sections) { section in
                Section {
                    LazyVGrid(columns: columns, spacing: LegacySpacing.md) {
                        ForEach(section.items) { item in
                            NavigationLink(value: item) {
                                MemoryLaneCard(
                                    item: item,
                                    isHighlighted: coordinator.highlightedMemoryIDs.contains(item.memoryID)
                                )
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                Task { await coordinator.loadMoreIfNeeded(current: item) }
                            }
                        }
                    }
                    .padding(.horizontal, LegacySpacing.lg)
                } header: {
                    MemoryLaneSectionHeader(title: section.title, count: section.items.count)
                }
            }
        }
        .padding(.vertical, LegacySpacing.lg)

        if coordinator.isLoadingMore {
            ProgressView()
                .tint(LegacyColor.accent)
                .padding(.bottom, LegacySpacing.lg)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if coordinator.mediaTypeFilter != .all {
            // Filtered to empty — guide the user back rather than to creation flows.
            ContentUnavailableView {
                Label("No matches", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text(emptyDescription)
            } actions: {
                Button("Clear filter") {
                    Task { await coordinator.setMediaTypeFilter(.all) }
                }
                .buttonStyle(.legacyPrimary)
            }
        } else {
            ContentUnavailableView {
                Label("No memories yet", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text(emptyDescription)
            } actions: {
                #if os(iOS)
                VStack(spacing: LegacySpacing.sm) {
                    if let onStartDropping {
                        Button("Drop your first memory", action: onStartDropping)
                            .buttonStyle(.legacyPrimary)
                    }
                    if let onStartImporting {
                        Button("Import from Photos", action: onStartImporting)
                            .buttonStyle(.legacySecondary)
                    }
                }
                .padding(.horizontal, LegacySpacing.xxl)
                #endif
            }
        }
    }

    private var emptyDescription: String {
        if coordinator.mediaTypeFilter != .all {
            return "No \(coordinator.mediaTypeFilter.label.lowercased()) match this filter."
        }
        return "Drop a photo or note at a place that matters — it'll appear here and unlock when you return."
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

/// Sticky year header for the sectioned Memory Lane grid.
private struct MemoryLaneSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LegacySpacing.sm) {
            Text(title)
                .font(LegacyFont.headline)
                .foregroundStyle(LegacyColor.textPrimary)
            Text(count == 1 ? "1 memory" : "\(count) memories")
                .font(LegacyFont.caption)
                .foregroundStyle(LegacyColor.textSecondary)
            Spacer()
        }
        .padding(.horizontal, LegacySpacing.lg)
        .padding(.vertical, LegacySpacing.sm)
        .background(
            LegacyColor.background.opacity(0.82),
            in: RoundedRectangle(cornerRadius: LegacyRadius.md, style: .continuous)
        )
        .padding(.horizontal, LegacySpacing.sm)
    }
}

private struct MemoryLaneSkeletonGallery: View {
    let columns: [GridItem]

    var body: some View {
        ScrollView {
            LegacyChromeCard(glow: Color(red: 0.80, green: 0.62, blue: 0.95)) {
                HStack {
                    RoundedRectangle(cornerRadius: LegacyRadius.sm, style: .continuous)
                        .fill(LegacyColor.surface.opacity(0.7))
                        .frame(width: 140, height: 16)
                    Spacer()
                    Circle()
                        .fill(LegacyColor.surface.opacity(0.7))
                        .frame(width: 24, height: 24)
                }
                .legacyShimmer()
            }
            .padding(.horizontal, LegacySpacing.lg)
            .padding(.top, LegacySpacing.sm)

            LazyVGrid(columns: columns, spacing: LegacySpacing.md) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: LegacySpacing.sm) {
                        RoundedRectangle(cornerRadius: LegacyRadius.sm, style: .continuous)
                            .fill(LegacyColor.surface.opacity(0.75))
                            .aspectRatio(1, contentMode: .fit)
                        RoundedRectangle(cornerRadius: LegacyRadius.sm, style: .continuous)
                            .fill(LegacyColor.surface.opacity(0.7))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: LegacyRadius.sm, style: .continuous)
                            .fill(LegacyColor.surface.opacity(0.5))
                            .frame(width: 90, height: 10)
                    }
                    .legacyShimmer()
                }
            }
            .padding(.horizontal, LegacySpacing.lg)
            .padding(.vertical, LegacySpacing.lg)
        }
    }
}

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

            Text(MemoryLaneFormatting.onThisDayLabel(dropDate: item.dropDate))
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

struct MemoryLaneCard: View {
    let item: MemoryLaneItem
    var isHighlighted: Bool = false

    private var isTextNote: Bool { item.mediaType == "text" }

    var body: some View {
        VStack(alignment: .leading, spacing: LegacySpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: LegacyRadius.sm)
                    .fill(
                        isTextNote
                            ? LinearGradient(
                                colors: [
                                    Color(red: 0.42, green: 0.34, blue: 0.22),
                                    Color(red: 0.28, green: 0.22, blue: 0.14),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [LegacyColor.surface, LegacyColor.background.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
                    .aspectRatio(1, contentMode: .fit)

                if isTextNote {
                    VStack(alignment: .leading, spacing: LegacySpacing.xs) {
                        Image(systemName: "scroll.fill")
                            .font(.title2)
                            .foregroundStyle(Color(red: 0.95, green: 0.88, blue: 0.72))
                        Text(item.displayLabel ?? item.teaserText ?? "Note in a bottle")
                            .font(LegacyFont.callout)
                            .foregroundStyle(Color(red: 0.95, green: 0.88, blue: 0.72))
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(LegacySpacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if let urlString = item.previewImageURL,
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
                            RoundedRectangle(cornerRadius: LegacyRadius.sm, style: .continuous)
                                .fill(LegacyColor.surface.opacity(0.7))
                                .legacyShimmer()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.sm))
                } else {
                    Image(systemName: item.mediaType == "text" ? "text.quote" : "photo")
                        .font(.title2)
                        .foregroundStyle(LegacyColor.textSecondary)
                }

                // Multi-photo badge: signals the memory holds the whole visit.
                if item.isMultiPhoto, let count = item.photoCount {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 3) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(LegacyColor.textOnAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(LegacyColor.accent, in: Capsule())
                            .padding(LegacySpacing.xs)
                        }
                        Spacer()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: LegacyRadius.sm)
                    .stroke(isHighlighted ? LegacyColor.accent : LegacyColor.separator, lineWidth: isHighlighted ? 2 : 1)
            )
            .accessibilityLabel(accessibilitySummary)

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

    private var accessibilitySummary: String {
        var parts = [item.dropDate]
        if isTextNote { parts.append("text note") }
        if let label = item.displayLabel { parts.append(label) }
        if item.isMultiPhoto, let count = item.photoCount { parts.append("\(count) photos") }
        if isHighlighted { parts.append("newly imported") }
        return parts.joined(separator: ", ")
    }
}

#if os(iOS)
struct MemoryLaneDetailView: View {
    let item: MemoryLaneItem
    @Bindable var coordinator: MemoryLaneCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

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

                    if let count = coordinator.detailReturnCount, count > 0 {
                        LabeledContent("Returns") {
                            Text(UnlockReturnNarrative.headline(returnCount: count))
                                .font(LegacyFont.body)
                        }
                    }

                    if let lastLabel = UnlockReturnNarrative.lastUnlockedLabel(iso8601: coordinator.detailLastFoundAt) {
                        LabeledContent("Last visit") {
                            Text(lastLabel.replacingOccurrences(of: "Last unlocked ", with: ""))
                                .font(LegacyFont.body)
                        }
                    }

                    LabeledContent("Status") {
                        VStack(alignment: .trailing, spacing: LegacySpacing.xxs) {
                            Text(lifecycleTitle(for: detail))
                                .font(LegacyFont.body)
                            if let status = detail.uploadStatus,
                               status.totalMedia > 0,
                               !status.isReady {
                                Text("\(status.uploadedMedia) of \(status.totalMedia) uploaded")
                                    .font(LegacyFont.caption)
                                    .foregroundStyle(LegacyColor.textSecondary)
                                ProgressView(value: status.progressFraction)
                                    .tint(LegacyColor.accent)
                                    .frame(width: 130)
                            }
                            if let status = detail.uploadStatus,
                               status.failedMedia > 0 {
                                Text("\(status.failedMedia) failed, retrying in background")
                                    .font(LegacyFont.caption)
                                    .foregroundStyle(LegacyColor.textSecondary)
                            }
                        }
                    }

                    if isReadyForViewing(detail) {
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

                    // Full photo set (hero-first) when the memory has cleared media; else
                    // fall back to the single owner/unlocked image.
                    let photos = (detail.media ?? []).sorted { $0.position < $1.position }
                    if !photos.isEmpty {
                        MemoryPhotoGallery(photos: photos)
                    } else if let url = coordinator.unlockedMediaURL ?? coordinator.ownerMediaURL {
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    if coordinator.isDeletingDetail {
                        ProgressView()
                    } else {
                        Image(systemName: "trash")
                    }
                }
                .disabled(coordinator.isDeletingDetail)
                .accessibilityLabel("Remove memory")
            }
        }
        .confirmationDialog(
            "Remove this memory?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove memory", role: .destructive) {
                Task {
                    let removed = await coordinator.deleteMemory(memoryID: item.memoryID)
                    if removed {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes the memory and its photos from your account.")
        }
        .task { await coordinator.loadDetail(for: item) }
    }

    private func isReadyForViewing(_ detail: MemoryDetail) -> Bool {
        detail.uploadStatus?.isReady ?? (detail.scanStatus == "clear")
    }

    private func lifecycleTitle(for detail: MemoryDetail) -> String {
        guard let status = detail.uploadStatus else {
            return detail.scanStatus == "clear" ? "Ready" : "Preparing memory"
        }
        switch status.stage {
        case "creating":
            return "Creating memory"
        case "uploading_hero":
            return "Uploading first photo"
        case "uploading_extras":
            return "Uploading remaining photos"
        case "partial_failure":
            return "Partially uploaded"
        case "ready":
            return "Ready"
        default:
            return detail.scanStatus == "clear" ? "Ready" : "Preparing memory"
        }
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
