import APIClient
import DesignSystem
import LocationEngine
import SwiftUI

#if os(iOS)
import SwiftData
import UIKit
#endif

/// V1 Pin, V2 Treasure Chest, and V4 Note in a Bottle drop flows.
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

    @State private var mode: DropTabMode = .pin
    @State private var compose = DropComposeDraft()
    @State private var showLibrary = false
    @State private var showCamera = false
    #endif

    public var body: some View {
        #if os(iOS)
        NavigationStack {
            VStack(spacing: LegacySpacing.md) {
                Picker("Drop mode", selection: $mode) {
                    ForEach(DropTabMode.allCases) { entry in
                        Label(entry.label, systemImage: entry.icon).tag(entry)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, LegacySpacing.lg)
                .padding(.top, LegacySpacing.sm)

                modeContent
                statusView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LegacyColor.background)
            .navigationTitle("Drop")
            .navigationBarTitleDisplayMode(.inline)
        }
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
        #else
        ContentUnavailableView("Drop", systemImage: "mappin.and.ellipse")
        #endif
    }

    #if os(iOS)
    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .pin:
            pinFlow
        case .treasure:
            VStack(spacing: 0) {
                treasurePhotoSection
                DropComposeViews.TreasureChestForm(
                    compose: $compose,
                    hasPhoto: coordinator.selectedPhotoData != nil,
                    isDropping: coordinator.isDropping,
                    onDrop: { Task { await coordinator.confirmTreasureDrop(compose: compose) } }
                )
            }
        case .note:
            DropComposeViews.NoteBottleForm(
                compose: $compose,
                isDropping: coordinator.isDropping,
                onDrop: { Task { await coordinator.dropNoteBottle(compose: compose) } }
            )
        }
    }

    private var treasurePhotoSection: some View {
        VStack(spacing: LegacySpacing.sm) {
            if let data = coordinator.selectedPhotoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md))
                    .padding(.horizontal, LegacySpacing.lg)
            }
            HStack(spacing: LegacySpacing.md) {
                Button("Library") { showLibrary = true }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Camera") { showCamera = true }
                }
                if coordinator.selectedPhotoData != nil {
                    Button("Clear") { coordinator.clearSelection() }
                }
            }
            .font(LegacyFont.callout)
            .foregroundStyle(LegacyColor.accent)
            .padding(.bottom, LegacySpacing.sm)
        }
    }

    private var pinFlow: some View {
        VStack(spacing: LegacySpacing.lg) {
            if !drafts.isEmpty {
                draftBanner
            }

            if let data = coordinator.selectedPhotoData, let image = UIImage(data: data) {
                photoPreview(image)
            } else {
                pickerPrompt
            }

            if case .succeeded = coordinator.state {
                Button("Drop another") {
                    coordinator.reset()
                    compose = DropComposeDraft()
                }
                .buttonStyle(.legacySecondary)
            }
        }
    }

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
                "Quick pin",
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
                .frame(maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md))
                .padding(.horizontal, LegacySpacing.lg)

            Button("Drop here") {
                Task { await coordinator.confirmPinDrop() }
            }
            .buttonStyle(.legacyPrimary)
            .padding(.horizontal, LegacySpacing.xl)
            .disabled(coordinator.isDropping)

            HStack(spacing: LegacySpacing.md) {
                Button("Library") { showLibrary = true }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Camera") { showCamera = true }
                }
                Button("Clear") { coordinator.clearSelection() }
            }
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
                .padding(.bottom, LegacySpacing.sm)
        case .failed(let message):
            Text(message)
                .font(LegacyFont.callout)
                .foregroundStyle(LegacyColor.danger)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LegacySpacing.lg)
                .padding(.bottom, LegacySpacing.sm)
        }
    }
}
