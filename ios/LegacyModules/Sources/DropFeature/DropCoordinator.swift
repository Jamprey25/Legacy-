import APIClient
import Foundation
import LocationEngine

public enum DropError: Error, Sendable, Equatable {
    case missingUpload
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
        uploader: MediaUploading = URLSessionMediaUploader()
    ) {
        self.apiClient = apiClient
        self.locationEngine = locationEngine
        self.uploader = uploader
    }

    private let apiClient: LegacyAPIClient
    private let locationEngine: LocationEngine
    private let uploader: MediaUploading

    public private(set) var selectedPhotoData: Data?
    public private(set) var pendingRecovery: PendingUploadRecovery?

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
            let stripped = try EXIFStripper.stripMetadata(from: photoData)
            strippedData = stripped
            let fix = try await locationEngine.acquireFix()
            fixLat = fix.lat
            fixLng = fix.lng

            state = .creating
            let body = makeCreateRequest(
                fix: fix,
                mediaType: "photo",
                dropMethod: dropMethod,
                compose: compose
            )
            let response = try await apiClient.createMemory(body)
            memoryID = response.memoryID

            guard
                let upload = response.upload,
                let url = URL(string: upload.signedPutURL)
            else {
                throw DropError.missingUpload
            }

            signedPutURL = upload.signedPutURL
            contentType = upload.headers["Content-Type"] ?? "image/jpeg"

            state = .uploading
            try await uploader.upload(data: stripped, to: url, contentType: contentType)

            #if DEBUG
            let ext = contentType.contains("mp4") ? "mp4" : "jpg"
            try? await apiClient.notifyUploadComplete(
                memoryID: response.memoryID,
                mediaKey: "memories/\(response.memoryID)/original.\(ext)"
            )
            #endif

            cacheOwnDrop(memoryID: response.memoryID, lat: fixLat, lng: fixLng)
            state = .succeeded(memoryID: response.memoryID)
        } catch DropError.missingUpload {
            state = .failed("Server did not return an upload URL.")
        } catch is EXIFStripError {
            state = .failed("Could not prepare photo for upload.")
        } catch let LegacyAPIError.invalidRequest(code, message) {
            state = .failed(message.isEmpty ? code : message)
            stageRecovery(memoryID: memoryID, photoData: strippedData, signedPutURL: signedPutURL, contentType: contentType)
        } catch {
            state = .failed("Drop failed. Check location permission and connectivity.")
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
            let body = makeCreateRequest(
                fix: fix,
                mediaType: "text",
                dropMethod: "note_bottle",
                compose: compose,
                caption: trimmed
            )
            let response = try await apiClient.createMemory(body)
            cacheOwnDrop(memoryID: response.memoryID, lat: fix.lat, lng: fix.lng)
            state = .succeeded(memoryID: response.memoryID)
        } catch let LegacyAPIError.invalidRequest(code, message) {
            state = .failed(message.isEmpty ? code : message)
        } catch {
            state = .failed("Could not drop your note. Check location and connectivity.")
        }
    }

    private func makeCreateRequest(
        fix: LocationFix,
        mediaType: String,
        dropMethod: String,
        compose: DropComposeDraft,
        caption: String? = nil
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
            condition: compose.condition.map(DropComposeMapping.conditionPayload(from:))
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
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        OwnMemoryPinCache.save(
            CachedOwnPin(
                memoryID: memoryID,
                lat: lat,
                lng: lng,
                dropDate: day.string(from: Date()),
                thumbnailURL: nil,
                cachedAt: Date()
            )
        )
    }
}
