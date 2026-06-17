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

    public private(set) var state: DropState = .idle
    public var isDropping: Bool {
        switch state {
        case .stripping, .creating, .uploading: return true
        default: return false
        }
    }

    public func reset() {
        state = .idle
    }

    /// Drop a photo at the current location. Caller supplies raw JPEG/HEIC bytes (picker wiring is separate).
    public func dropPin(photoData: Data) async {
        guard !isDropping else { return }

        state = .stripping

        do {
            let stripped = try EXIFStripper.stripMetadata(from: photoData)
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

            guard
                let upload = response.upload,
                let url = URL(string: upload.signedPutURL)
            else {
                throw DropError.missingUpload
            }

            state = .uploading
            let contentType = upload.headers["Content-Type"] ?? "image/jpeg"
            try await uploader.upload(data: stripped, to: url, contentType: contentType)

            state = .succeeded(memoryID: response.memoryID)
        } catch DropError.missingUpload {
            state = .failed("Server did not return an upload URL.")
        } catch is EXIFStripError {
            state = .failed("Could not prepare photo for upload.")
        } catch let LegacyAPIError.invalidRequest(code, message) {
            state = .failed(message.isEmpty ? code : message)
        } catch {
            state = .failed("Drop failed. Check location permission and connectivity.")
        }
    }
}
