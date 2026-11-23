import Foundation
import UniformTypeIdentifiers

@MainActor
struct CaptureInitialVideoAttempt {
    let fileURL: URL
    let facts: SharedMediaCaptureSourceFacts
    let recipe: SharedMediaCaptureDraftJournal.VideoRecipe
    var companion: CaptureScanTemporaryFileLease?
}

/// Exact bytes retained in memory across an uncertain local write. This is a
/// retry input, never proof of durable custody. The journal owns cold recovery.
@MainActor
struct CaptureInitialSourceAttempt {
    static func imageContentType(for bytes: Data) throws -> String {
        let identifier = try PhotoPreparationLockedFiles.validateImage(bytes, maximumBytes: PhotoPreparationPolicy.original)
        guard let mime = UTType(identifier)?.preferredMIMEType else { throw SharedMediaStorageFailure.invalid }
        try SharedMediaCaptureArtifactRequest.Role.sourceImage.require(contentType: mime, byteCount: Int64(bytes.count), frameIndex: nil)
        return mime
    }
    let itemID: UUID
    let bytes: Data
    let role: SharedMediaCaptureArtifactRequest.Role
    let contentType: String
    let context: SharedMediaCaptureDraftSourceContext
    let review: CaptureInitialDraftSession.Review?

    var retention: CaptureInitialDraftSession.Retention {
        .init(itemID: itemID, bytes: bytes, role: role, contentType: contentType, context: context, review: review)
    }

    func retain(in session: CaptureInitialDraftSession) async throws {
        _ = try await session.retain(itemID: itemID, bytes: bytes, role: role,
            contentType: contentType, context: context, review: review)
    }
}
