#if os(iOS)
import Foundation
import SwiftData

@MainActor
public enum DropDraftRecovery {
    public static func retryPendingDrafts(context: ModelContext) async {
        let descriptor = FetchDescriptor<DropDraft>(
            predicate: #Predicate { $0.uploadState == "pending_upload" }
        )
        guard let drafts = try? context.fetch(descriptor), !drafts.isEmpty else { return }

        let uploader = BackgroundMediaUploader()
        for draft in drafts {
            guard
                let data = DropDraftStore.photoData(for: draft),
                let url = URL(string: draft.signedPutURL)
            else { continue }

            do {
                try await uploader.upload(data: data, to: url, contentType: draft.contentType)
                try DropDraftStore.delete(draft, context: context)
            } catch {
                draft.uploadState = "failed"
                try? context.save()
            }
        }
    }
}
#endif
