import Foundation

/// The complete immutable local observation plus matching acknowledgements for
/// every client-uploaded role. Server DSP outputs are deliberately absent.
/// Callers still require current account, storage and network authorization.
@MainActor
enum SharedMediaCaptureUploadReadiness {
    static func require(_ snapshot: SharedMediaCaptureSubmissionReceipt.Snapshot) throws -> String {
        guard snapshot.release == nil, case .accepted = snapshot.state,
              snapshot.artifacts.count == snapshot.submission.members.count else { throw SharedMediaStorageFailure.conflict }
        var serverChecksum: String?
        for (member, artifact) in zip(snapshot.submission.members, snapshot.artifacts) {
            try snapshot.submission.requireMember(artifact)
            guard artifact.request.id == member.artifactID, artifact.request.mediaID == member.mediaID,
                  !artifact.isRetiring, artifact.phase == .ready, let stage = artifact.stage, let remote = artifact.remoteStage else {
                throw SharedMediaStorageFailure.conflict
            }
            try remote.validate(request: artifact.request, stage: stage)
            guard serverChecksum == nil || serverChecksum == remote.serverRequestSHA256 else {
                throw SharedMediaStorageFailure.conflict
            }
            serverChecksum = remote.serverRequestSHA256
        }
        guard let serverChecksum else { throw SharedMediaStorageFailure.conflict }
        return serverChecksum
    }
}
