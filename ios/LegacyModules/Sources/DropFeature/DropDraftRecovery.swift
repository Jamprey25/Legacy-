#if os(iOS)
import APIClient
import Foundation
import SwiftData

@MainActor
public enum DropDraftRecovery {
    public static func retryPendingDrafts(context: ModelContext, mediaUploader: MemoryMediaUploader) async {
        let descriptor = FetchDescriptor<DropDraft>(
            predicate: #Predicate { $0.uploadState == "pending_upload" }
        )
        guard let drafts = try? context.fetch(descriptor), !drafts.isEmpty else { return }

        let presignedUploader = URLSessionMediaUploader()

        for draft in drafts {
            guard let data = DropDraftStore.photoData(for: draft) else { continue }

            do {
                if VercelBlobUpload.isDraftRecoveryMarker(draft.signedPutURL) {
                    _ = try await mediaUploader.upload(
                        memoryID: draft.memoryID,
                        data: data,
                        contentType: draft.contentType,
                        signedPutURL: nil
                    )
                } else if let url = URL(string: draft.signedPutURL) {
                    try await presignedUploader.upload(data: data, to: url, contentType: draft.contentType)
                } else {
                    continue
                }
                try DropDraftStore.delete(draft, context: context)
            } catch {
                draft.uploadState = "failed"
                try? context.save()
            }
        }
    }
}
#endif
