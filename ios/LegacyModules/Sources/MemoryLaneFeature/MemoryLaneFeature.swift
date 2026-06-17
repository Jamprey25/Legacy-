import APIClient
import DesignSystem
import SwiftUI

/// Grid of own memories — oldest first, no proximity check for owner content.
public enum MemoryLaneFeature {
    public static let version = "0.1.0"
}

@MainActor
@Observable
public final class MemoryLaneCoordinator {
    public init(apiClient: LegacyAPIClient) {
        self.apiClient = apiClient
    }

    private let apiClient: LegacyAPIClient
    private var nextCursor: String?

    public private(set) var items: [MemoryLaneItem] = []
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var errorMessage: String?

    public var canLoadMore: Bool { nextCursor != nil }

    public func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await apiClient.listMemories()
            items = response.memories
            nextCursor = response.nextCursor
        } catch {
            errorMessage = "Could not load your memories."
        }
    }

    public func loadMoreIfNeeded(current item: MemoryLaneItem) async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        guard item.id == items.last?.id else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let response = try await apiClient.listMemories(cursor: cursor)
            items.append(contentsOf: response.memories)
            nextCursor = response.nextCursor
        } catch {
            errorMessage = "Could not load more memories."
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
                        description: Text("Memories you drop will appear here, oldest first.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: LegacySpacing.md) {
                            ForEach(coordinator.items) { item in
                                MemoryLaneCard(item: item)
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
                    }
                }
            }
            .background(LegacyColor.background)
            .navigationTitle("Memory Lane")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
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
}

private struct MemoryLaneCard: View {
    let item: MemoryLaneItem

    var body: some View {
        VStack(alignment: .leading, spacing: LegacySpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: LegacyRadius.sm)
                    .fill(LegacyColor.surface)
                    .aspectRatio(1, contentMode: .fit)
                Image(systemName: item.mediaType == "text" ? "text.quote" : "photo")
                    .font(.title2)
                    .foregroundStyle(LegacyColor.textSecondary)
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
