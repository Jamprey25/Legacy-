import APIClient
import DesignSystem
import LocationEngine
import SwiftUI

#if os(iOS)
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
    @State private var showLibrary = false
    @State private var showCamera = false
    #endif

    public var body: some View {
        VStack(spacing: LegacySpacing.lg) {
            #if os(iOS)
            if let data = coordinator.selectedPhotoData, let image = UIImage(data: data) {
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
            } else {
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
