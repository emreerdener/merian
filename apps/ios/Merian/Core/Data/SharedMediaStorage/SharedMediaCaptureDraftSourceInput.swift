import Foundation

/// Shutter/import facts needed to restore the original's initial presentation.
/// Later crop, selection and ordering belong to the final observation plan.
struct SharedMediaCaptureDraftSourceContext: Codable, Equatable, Sendable {
    enum Origin: String, Codable, Sendable { case camera, imported, microphone, videoAudio }
    let origin: Origin
    let cameraVerticalCenter: Double?
    let facts: SharedMediaCaptureSourceFacts?

    init(origin: Origin, cameraVerticalCenter: Double?, facts: SharedMediaCaptureSourceFacts? = nil) {
        self.origin = origin; self.cameraVerticalCenter = cameraVerticalCenter; self.facts = facts
    }

    func validate(role: SharedMediaCaptureArtifactRequest.Role) throws {
        try facts?.validate()
        switch role {
        case .sourceImage, .sourceVideo:
            guard origin == .camera || origin == .imported else { throw SharedMediaStorageFailure.conflict }
        case .sourceAudio:
            guard origin == .microphone || origin == .imported else { throw SharedMediaStorageFailure.conflict }
        case .sourceCompanionAudio:
            guard origin == .videoAudio else { throw SharedMediaStorageFailure.conflict }
        default: throw SharedMediaStorageFailure.conflict
        }
        if origin == .camera {
            guard let cameraVerticalCenter, cameraVerticalCenter.isFinite,
                  (0...1).contains(cameraVerticalCenter) else { throw SharedMediaStorageFailure.conflict }
        } else if cameraVerticalCenter != nil { throw SharedMediaStorageFailure.conflict }
    }
}

/// Immutable pre-Identify source facts. The scan/generation pair is retained
/// for this entire draft; itemIndex is a stable source ordinal, not UI order.
/// This value grants no filesystem, upload or submission authority.
struct SharedMediaCaptureDraftSourceInput: Codable, Equatable, Sendable {
    let id: UUID
    let scanID: UUID
    let submissionGeneration: UUID
    let mediaID: UUID
    let itemIndex: Int
    let role: SharedMediaCaptureArtifactRequest.Role
    let contentType: String
    let byteCount: Int64
    let sha256: String
    let context: SharedMediaCaptureDraftSourceContext
}
