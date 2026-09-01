import Foundation

struct InsightCandidateSwipeDismissalRequest: Equatable {
    let request: CandidateSwipeDismissalRequest
    let localPresentationGeneration: UInt64
}

enum InsightContentPresentation: Identifiable, Equatable {
    case gallery(InsightImageGalleryPresentation, scanId: String, generation: UInt64)
    case candidate(scanId: String, generation: UInt64, engineGeneration: UInt64)
    case community(scanId: String, generation: UInt64, requestId: String?)
    case composer(scanId: String, generation: UInt64, postId: String)
    case fieldNotes(scanId: String, generation: UInt64)
    case safari(scanId: String, generation: UInt64, url: URL)
    case observation(scanId: String, generation: UInt64)

    var id: String {
        switch self {
        case .gallery(let presentation, let scanId, let generation):
            "gallery-\(scanId)-\(generation)-\(presentation.id)"
        case .candidate(let scanId, let generation, let engineGeneration):
            "candidate-\(scanId)-\(generation)-\(engineGeneration)"
        case .community(let scanId, let generation, let requestId):
            "community-\(scanId)-\(generation)-\(requestId ?? "new")"
        case .composer(let scanId, let generation, let postId):
            "composer-\(scanId)-\(generation)-\(postId)"
        case .fieldNotes(let scanId, let generation):
            "field-notes-\(scanId)-\(generation)"
        case .safari(let scanId, let generation, let url):
            "safari-\(scanId)-\(generation)-\(url.absoluteString)"
        case .observation(let scanId, let generation):
            "observation-\(scanId)-\(generation)"
        }
    }

    var usesFullscreenCover: Bool {
        if case .gallery = self {
            return true
        }
        return false
    }
}
