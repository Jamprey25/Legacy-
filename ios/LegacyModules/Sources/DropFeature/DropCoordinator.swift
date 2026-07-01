import APIClient
import Foundation
import LocationEngine

#if os(iOS)
import SwiftData
#endif

public enum DropError: Error, Sendable, Equatable {
    case stripFailed
    case emptyNote
}

public enum DropState: Sendable, Equatable {
    case idle
    case stripping
    case creating
    case uploading
    case succeeded(memoryID: String)
    case failed(String)
}

/// Orchestrates pin, treasure chest, and note-in-a-bottle drops.
@MainActor
@Observable
public final class DropCoordinator {
    public init(
        apiClient: LegacyAPIClient,
        locationEngine: LocationEngine,
        mediaUploader: MemoryMediaUploader? = nil
    ) {
        self.apiClient = apiClient
        self.locationEngine = locationEngine
        self.mediaUploader = mediaUploader ?? MemoryMediaUploader(apiClient: apiClient)
    }

    private let apiClient: LegacyAPIClient
    private let locationEngine: LocationEngine
    private let mediaUploader: MemoryMediaUploader

    public private(set) var selectedPhotoData: Data?
    public private(set) var pendingRecovery: PendingUploadRecovery?
    public private(set) var pendingCelebrationPin: CachedOwnPin?

    /// Exposed for compose subviews (summons preview UI).
    public var apiClientForSummons: LegacyAPIClient { apiClient }

    public func consumeCelebrationPin() -> CachedOwnPin? {
        defer { pendingCelebrationPin = nil }
        return pendingCelebrationPin
    }

    public private(set) var state: DropState = .idle
    public var isDropping: Bool {
        switch state {
        case .stripping, .creating, .uploading: return true
        default: return false
        }
    }

    public func reset() {
        state = .idle
        selectedPhotoData = nil
    }

    public func selectPhoto(_ data: Data) {
        selectedPhotoData = data
        state = .idle
    }

    public func clearSelection() {
        selectedPhotoData = nil
    }

    public func clearPendingRecovery() {
        pendingRecovery = nil
    }

    public func confirmPinDrop() async {
        guard let data = selectedPhotoData else { return }
        await dropPhoto(photoData: data, dropMethod: "pin", compose: .pinDefault)
        if case .succeeded = state {
            selectedPhotoData = nil
        }
    }

    public func confirmTreasureDrop(compose: DropComposeDraft) async {
        guard let data = selectedPhotoData else { return }
        await dropPhoto(photoData: data, dropMethod: "treasure_chest", compose: compose)
        if case .succeeded = state {
            selectedPhotoData = nil
        }
    }

    public func dropNoteBottle(compose: DropComposeDraft) async {
        await dropTextNote(compose: compose)
    }

    private func dropPhoto(photoData: Data, dropMethod: String, compose: DropComposeDraft) async {
        guard !isDropping else { return }

        state = .stripping
        pendingRecovery = nil

        var strippedData: Data?
        var memoryID: String?
        var signedPutURL: String?
        var contentType = "image/jpeg"
        var fixLat = 0.0
        var fixLng = 0.0

        do {
            // Downsample single drops too (1280px / q0.7) — same cap as import so a handful of
            // full-resolution drops can't fill blob storage. stripMetadata (no resize) remains
            // available for any caller that needs the original pixels.
            let stripped = try EXIFStripper.downsampledStrippedJPEG(
                from: photoData, maxPixelSize: 1280, quality: 0.7
            )
            strippedData = stripped
            let fix = try await locationEngine.acquireFix()
            fixLat = fix.lat
            fixLng = fix.lng

            state = .creating
            let appAttest = await AppAttestBridge.currentAssertion()
            let body = makeCreateRequest(
                fix: fix,
                mediaType: "photo",
                dropMethod: dropMethod,
                compose: compose,
                appAttest: appAttest
            )
            let response = try await apiClient.createMemory(body)
            memoryID = response.memoryID
            contentType = response.upload?.headers["Content-Type"] ?? "image/jpeg"

            if let upload = response.upload {
                signedPutURL = upload.signedPutURL
            } else {
                signedPutURL = VercelBlobUpload.draftRecoveryMarker
            }

            state = .uploading
            let blobURL = try await mediaUploader.upload(
                memoryID: response.memoryID,
                data: stripped,
                contentType: contentType,
                signedPutURL: response.upload?.signedPutURL,
                uploadHeaders: response.upload?.headers ?? [:]
            )

            #if DEBUG
            if response.upload == nil {
                let mediaKey = blobURL ?? VercelBlobUpload.pathname(
                    memoryID: response.memoryID,
                    contentType: contentType
                )
                try? await apiClient.notifyUploadComplete(
                    memoryID: response.memoryID,
                    mediaKey: mediaKey
                )
            } else {
                let ext = contentType.contains("mp4") ? "mp4" : "jpg"
                try? await apiClient.notifyUploadComplete(
                    memoryID: response.memoryID,
                    mediaKey: "memories/\(response.memoryID)/original.\(ext)"
                )
            }
            #endif

            let dropDay = Self.dropDateString()
            cacheOwnDrop(memoryID: response.memoryID, lat: fixLat, lng: fixLng)
            pendingCelebrationPin = CachedOwnPin(
                memoryID: response.memoryID,
                lat: fixLat,
                lng: fixLng,
                dropDate: dropDay,
                thumbnailURL: nil,
                cachedAt: Date()
            )
            state = .succeeded(memoryID: response.memoryID)
            await sendSummonsIfNeeded(memoryID: response.memoryID, compose: compose)
        } catch LocationEngineError.simulatedLocation {
            state = .failed("Simulated location is not allowed for drops.")
        } catch is EXIFStripError {
            state = .failed("Could not prepare photo for upload.")
        } catch let LegacyAPIError.invalidRequest(code, message) {
            state = .failed(message.isEmpty ? code : message)
            stageRecovery(memoryID: memoryID, photoData: strippedData, signedPutURL: signedPutURL, contentType: contentType)
        } catch let LegacyAPIError.server(status) {
            state = .failed("Server error (\(status)) creating memory.")
            stageRecovery(memoryID: memoryID, photoData: strippedData, signedPutURL: signedPutURL, contentType: contentType)
        } catch let error as LegacyAPIError where error.isAppAttestFailure {
            state = .failed("Device attestation failed. Reopen Legacy and try again on a real device.")
        } catch LegacyAPIError.unauthorized {
            state = .failed("Session expired. Sign out and sign in again.")
        } catch let error as MediaUploadError {
            state = .failed(dropUploadMessage(for: error))
            stageRecovery(memoryID: memoryID, photoData: strippedData, signedPutURL: signedPutURL, contentType: contentType)
        } catch let error as BlobUploadError {
            state = .failed(blobUploadMessage(for: error))
            stageRecovery(memoryID: memoryID, photoData: strippedData, signedPutURL: signedPutURL, contentType: contentType)
        } catch {
            state = .failed("Drop failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            stageRecovery(memoryID: memoryID, photoData: strippedData, signedPutURL: signedPutURL, contentType: contentType)
        }
    }

    private func dropTextNote(compose: DropComposeDraft) async {
        guard !isDropping else { return }
        let trimmed = compose.noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .failed("Write something for your note.")
            return
        }

        state = .creating
        pendingRecovery = nil

        do {
            let fix = try await locationEngine.acquireFix()
            let appAttest = await AppAttestBridge.currentAssertion()
            let body = makeCreateRequest(
                fix: fix,
                mediaType: "text",
                dropMethod: "note_bottle",
                compose: compose,
                caption: trimmed,
                appAttest: appAttest
            )
            let response = try await apiClient.createMemory(body)
            let dropDay = Self.dropDateString()
            cacheOwnDrop(memoryID: response.memoryID, lat: fix.lat, lng: fix.lng)
            pendingCelebrationPin = CachedOwnPin(
                memoryID: response.memoryID,
                lat: fix.lat,
                lng: fix.lng,
                dropDate: dropDay,
                thumbnailURL: nil,
                cachedAt: Date()
            )
            state = .succeeded(memoryID: response.memoryID)
        } catch let error as LegacyAPIError where error.isAppAttestFailure {
            state = .failed("Device attestation failed. Reopen Legacy and try again on a real device.")
        } catch LegacyAPIError.unauthorized {
            state = .failed("Session expired. Sign out and sign in again.")
        } catch let LegacyAPIError.invalidRequest(code, message) {
            state = .failed(message.isEmpty ? code : message)
        } catch {
            state = .failed("Could not drop your note. Check location and connectivity.")
        }
    }

    private func sendSummonsIfNeeded(memoryID: String, compose: DropComposeDraft) async {
        guard !compose.recipientPhones.isEmpty else { return }
        let label = compose.teaserText.trimmingCharacters(in: .whitespacesAndNewlines)
        try? await apiClient.sendSummons(
            memoryID: memoryID,
            recipients: compose.recipientPhones,
            placeLabel: label.isEmpty ? nil : label
        )
    }

    private func makeCreateRequest(
        fix: LocationFix,
        mediaType: String,
        dropMethod: String,
        compose: DropComposeDraft,
        caption: String? = nil,
        appAttest: AppAttestAssertionPayload? = nil
    ) -> CreateMemoryRequest {
        let teaser = compose.teaserText.trimmingCharacters(in: .whitespacesAndNewlines)
        return CreateMemoryRequest(
            lat: fix.lat,
            lng: fix.lng,
            accuracyM: fix.accuracyM,
            mediaType: mediaType,
            dropMethod: dropMethod,
            privacyTier: compose.privacyTier.isAvailableInPhase1 ? compose.privacyTier.rawValue : "private",
            teaserText: teaser.isEmpty ? nil : teaser,
            caption: caption,
            seal: DropComposeMapping.sealPayload(from: compose.seal),
            condition: compose.condition.map(DropComposeMapping.conditionPayload(from:)),
            attestation: appAttest?.attestation,
            challengeToken: appAttest?.challengeToken
        )
    }

    private func stageRecovery(
        memoryID: String?,
        photoData: Data?,
        signedPutURL: String?,
        contentType: String
    ) {
        guard let memoryID, let photoData, let signedPutURL else { return }
        pendingRecovery = PendingUploadRecovery(
            memoryID: memoryID,
            photoData: photoData,
            signedPutURL: signedPutURL,
            contentType: contentType
        )
    }

    private func cacheOwnDrop(memoryID: String, lat: Double, lng: Double) {
        OwnMemoryPinCache.save(
            CachedOwnPin(
                memoryID: memoryID,
                lat: lat,
                lng: lng,
                dropDate: Self.dropDateString(),
                thumbnailURL: nil,
                cachedAt: Date()
            )
        )
    }

    private static func dropDateString() -> String {
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        return day.string(from: Date())
    }

    #if os(iOS)
    /// Retries a persisted draft — presigned PUT or Vercel Blob handshake.
    public func retryDraft(_ draft: DropDraft, context: ModelContext) async {
        guard let data = DropDraftStore.photoData(for: draft) else { return }

        do {
            if VercelBlobUpload.isDraftRecoveryMarker(draft.signedPutURL) {
                _ = try await mediaUploader.upload(
                    memoryID: draft.memoryID,
                    data: data,
                    contentType: draft.contentType,
                    signedPutURL: nil
                )
            } else if let url = TrustedMediaURL.uploadURL(from: draft.signedPutURL) {
                try await URLSessionMediaUploader().upload(
                    data: data,
                    to: url,
                    contentType: draft.contentType
                )
            } else {
                return
            }
            try DropDraftStore.delete(draft, context: context)
        } catch {
            draft.uploadState = "failed"
            try? context.save()
        }
    }
    #endif

    private func dropUploadMessage(for error: MediaUploadError) -> String {
        switch error {
        case let .transport(message):
            return "Upload failed: \(message)"
        case let .invalidResponse(statusCode):
            return "Upload failed (HTTP \(statusCode))."
        }
    }

    private func blobUploadMessage(for error: BlobUploadError) -> String {
        switch error {
        case .invalidClientToken:
            return "Upload token invalid. Sign out and try again."
        case let .tokenRequestFailed(statusCode):
            return "Could not start upload (HTTP \(statusCode)). Check you're signed in."
        case let .uploadFailed(statusCode):
            return "Blob upload failed (HTTP \(statusCode))."
        case let .transport(message):
            return "Upload failed: \(message)"
        }
    }
}
