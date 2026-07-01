import Foundation

/// In-memory recovery state for an upload that failed after POST /memories succeeded.
public struct PendingUploadRecovery: Sendable, Equatable {
    public let memoryID: String
    public let photoData: Data
    public let signedPutURL: String
    public let contentType: String

    public init(memoryID: String, photoData: Data, signedPutURL: String, contentType: String) {
        self.memoryID = memoryID
        self.photoData = photoData
        self.signedPutURL = signedPutURL
        self.contentType = contentType
    }
}

#if os(iOS)
import SwiftData

/// Persisted interrupted drop — photo bytes on disk, memory_id from POST /memories.
/// Never stores coordinates (SEC-LOC-1).
@Model
public final class DropDraft {
    @Attribute(.unique) public var id: UUID
    public var memoryID: String
    public var imageFileName: String
    public var signedPutURL: String
    public var contentType: String
    /// `pending_upload` | `failed`
    public var uploadState: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        memoryID: String,
        imageFileName: String,
        signedPutURL: String,
        contentType: String,
        uploadState: String = "pending_upload",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.memoryID = memoryID
        self.imageFileName = imageFileName
        self.signedPutURL = signedPutURL
        self.contentType = contentType
        self.uploadState = uploadState
        self.createdAt = createdAt
    }
}

@MainActor
public enum DropDraftStore {
    public static let draftsDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("DropDrafts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    public static func saveDraft(
        memoryID: String,
        strippedPhoto: Data,
        signedPutURL: String,
        contentType: String,
        context: ModelContext
    ) throws {
        let fileName = "\(memoryID).jpg"
        let fileURL = draftsDirectory.appendingPathComponent(fileName)
        try strippedPhoto.write(to: fileURL, options: .atomic)

        let draft = DropDraft(
            memoryID: memoryID,
            imageFileName: fileName,
            signedPutURL: signedPutURL,
            contentType: contentType
        )
        context.insert(draft)
        try context.save()
    }

    public static func photoData(for draft: DropDraft) -> Data? {
        let url = draftsDirectory.appendingPathComponent(draft.imageFileName)
        return try? Data(contentsOf: url)
    }

    public static func delete(_ draft: DropDraft, context: ModelContext) throws {
        let url = draftsDirectory.appendingPathComponent(draft.imageFileName)
        try? FileManager.default.removeItem(at: url)
        context.delete(draft)
        try context.save()
    }

    /// Wipe all interrupted-drop drafts and photo files (sign-out / account delete).
    public static func purgeAll(context: ModelContext) throws {
        let descriptor = FetchDescriptor<DropDraft>()
        let drafts = try context.fetch(descriptor)
        for draft in drafts {
            let url = draftsDirectory.appendingPathComponent(draft.imageFileName)
            try? FileManager.default.removeItem(at: url)
            context.delete(draft)
        }
        if !drafts.isEmpty {
            try context.save()
        }
        try? FileManager.default.removeItem(at: draftsDirectory)
        try? FileManager.default.createDirectory(at: draftsDirectory, withIntermediateDirectories: true)
    }
}
#endif
