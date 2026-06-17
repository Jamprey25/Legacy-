import APIClient
import Foundation
import LocationEngine

public enum DropError: Error, Sendable, Equatable {
    case missingUpload
    case stripFailed
}

public enum DropState: Sendable, Equatable {
    case idle
    case stripping
    case creating
    case uploading
    case succeeded(memoryID: String)
    case failed(String)
}

/// Orchestrates V1 pin drop: strip EXIF → POST /memories → PUT to signed URL.
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

    public func confirmDrop() async {
        guard let data = selectedPhotoData else { return }
        await dropPin(photoData: data)
        if case .succeeded = state {
            selectedPhotoData = nil
        }
    }

    /// Drop a photo at the current location. Caller supplies raw JPEG/HEIC bytes (picker wiring is separate).
    public func dropPin(photoData: Data) async {
        guard !isDropping else { return }

        state = .stripping
        pendingRecovery = nil

        var strippedData: Data?
        var memoryID: String?
        var signedPutURL: String?
        var contentType = "image/jpeg"

        do {
            let stripped = try EXIFStripper.stripMetadata(from: photoData)
            strippedData = stripped
            let fix = try await locationEngine.acquireFix()

            state = .creating
            let body = CreateMemoryRequest(
                lat: fix.lat,
                lng: fix.lng,
                accuracyM: fix.accuracyM,
                mediaType: "photo",
                dropMethod: "pin"
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

            // In DEBUG, notify the backend so the CSAM stub flips scan_status → clear.
            // In production, the storage provider fires this webhook server-to-server.
            // mediaKey mirrors the backend convention: memories/<id>/original.<ext>
            #if DEBUG
            let ext = contentType.contains("mp4") ? "mp4" : "jpg"
            try? await apiClient.notifyUploadComplete(
                memoryID: response.memoryID,
                mediaKey: "memories/\(response.memoryID)/original.\(ext)"
            )
            #endif

            state = .succeeded(memoryID: response.memoryID)
        } catch DropError.missingUpload {
            state = .failed("Server did not return an upload URL.")
        } catch is EXIFStripError {
            state = .failed("Could not prepare photo for upload.")
        } catch let LegacyAPIError.invalidRequest(code, message) {
            state = .failed(message.isEmpty ? code : message)
            if let memoryID, let strippedData, let signedPutURL {
                pendingRecovery = PendingUploadRecovery(
                    memoryID: memoryID,
                    photoData: strippedData,
                    signedPutURL: signedPutURL,
                    contentType: contentType
                )
            }
        } catch {
            state = .failed("Drop failed. Check location permission and connectivity.")
            if let memoryID, let strippedData, let signedPutURL {
                pendingRecovery = PendingUploadRecovery(
                    memoryID: memoryID,
                    photoData: strippedData,
                    signedPutURL: signedPutURL,
                    contentType: contentType
                )
            }
        }
    }
}
