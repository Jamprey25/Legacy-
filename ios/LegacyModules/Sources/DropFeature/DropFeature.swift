import APIClient
import DesignSystem
import LocationEngine
import SwiftUI

#if os(iOS)
import SwiftData
import UIKit
#endif

/// V1 Pin and V2 Treasure Chest drop flows.
public enum DropFeature {
    public static let version = "0.1.0"
}

public struct DropFeatureRootView: View {
    public init(coordinator: DropCoordinator) {
        self.coordinator = coordinator
    }

    @Bindable private var coordinator: DropCoordinator

    #if os(iOS)
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DropDraft.createdAt, order: .reverse) private var drafts: [DropDraft]

    @State private var showLibrary = false
    @State private var showCamera = false
    #endif

    public var body: some View {
        VStack(spacing: LegacySpacing.lg) {
            #if os(iOS)
            if !drafts.isEmpty {
                draftBanner
            }

            if let data = coordinator.selectedPhotoData, let image = UIImage(data: data) {
                photoPreview(image)
            } else {
                pickerPrompt
            }
            #else
            ContentUnavailableView("Drop", systemImage: "mappin.and.ellipse")
            #endif

            statusView

            if case .succeeded = coordinator.state {
                Button("Drop another") { coordinator.reset() }
                    .buttonStyle(.legacySecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LegacyColor.background)
        #if os(iOS)
        .onChange(of: coordinator.pendingRecovery) { _, recovery in
            guard let recovery else { return }
            try? DropDraftStore.saveDraft(
                memoryID: recovery.memoryID,
                strippedPhoto: recovery.photoData,
                signedPutURL: recovery.signedPutURL,
                contentType: recovery.contentType,
                context: modelContext
            )
            coordinator.clearPendingRecovery()
        }
        .sheet(isPresented: $showLibrary) {
            PhotoLibraryPicker(
                onPick: { data in
                    showLibrary = false
                    coordinator.selectPhoto(data)
                },
                onCancel: { showLibrary = false }
            )
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                onPick: { data in
                    showCamera = false
                    coordinator.selectPhoto(data)
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        #endif
    }

    #if os(iOS)
    private var draftBanner: some View {
        VStack(alignment: .leading, spacing: LegacySpacing.sm) {
            Text("Pending uploads")
                .font(LegacyFont.headline)
                .foregroundStyle(LegacyColor.textPrimary)
            ForEach(drafts) { draft in
                HStack {
                    VStack(alignment: .leading, spacing: LegacySpacing.xxs) {
                        Text(String(draft.memoryID.prefix(8)) + "…")
                            .font(LegacyFont.caption)
                        Text(draft.uploadState == "failed" ? "Upload failed" : "Waiting to upload")
                            .font(LegacyFont.caption)
                            .foregroundStyle(LegacyColor.textSecondary)
                    }
                    Spacer()
                    Button("Retry") {
                        Task { await retryDraft(draft) }
                    }
                    .buttonStyle(.legacyPrimary)
                    .frame(maxWidth: 100)
                }
                .padding(LegacySpacing.md)
                .background(LegacyColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.sm))
            }
        }
        .padding(.horizontal, LegacySpacing.lg)
    }

    private var pickerPrompt: some View {
        Group {
            ContentUnavailableView(
                "Drop",
                systemImage: "mappin.and.ellipse",
                description: Text("Pin a photo at your current location.")
            )

            VStack(spacing: LegacySpacing.md) {
                Button("Choose from Library") { showLibrary = true }
                    .buttonStyle(.legacyPrimary)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { showCamera = true }
                        .buttonStyle(.legacySecondary)
                }
            }
            .padding(.horizontal, LegacySpacing.xl)
        }
    }

    private func photoPreview(_ image: UIImage) -> some View {
        Group {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md))
                .padding(.horizontal, LegacySpacing.lg)

            Button("Drop here") {
                Task { await coordinator.confirmDrop() }
            }
            .buttonStyle(.legacyPrimary)
            .padding(.horizontal, LegacySpacing.xl)
            .disabled(coordinator.isDropping)

            Button("Choose a different photo") { coordinator.clearSelection() }
                .font(LegacyFont.callout)
                .foregroundStyle(LegacyColor.textSecondary)
        }
    }

    private func retryDraft(_ draft: DropDraft) async {
        guard let data = DropDraftStore.photoData(for: draft),
              let url = URL(string: draft.signedPutURL) else { return }
        let uploader = URLSessionMediaUploader()
        do {
            try await uploader.upload(data: data, to: url, contentType: draft.contentType)
            try DropDraftStore.delete(draft, context: modelContext)
        } catch {
            draft.uploadState = "failed"
            try? modelContext.save()
        }
    }
    #endif

    @ViewBuilder
    private var statusView: some View {
        switch coordinator.state {
        case .idle:
            EmptyView()
        case .stripping, .creating, .uploading:
            ProgressView("Dropping memory…")
                .tint(LegacyColor.accent)
        case .succeeded:
            Text("Memory dropped.")
                .font(LegacyFont.callout)
                .foregroundStyle(LegacyColor.accent)
        case .failed(let message):
            Text(message)
                .font(LegacyFont.callout)
                .foregroundStyle(LegacyColor.danger)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LegacySpacing.lg)
        }
    }
}
