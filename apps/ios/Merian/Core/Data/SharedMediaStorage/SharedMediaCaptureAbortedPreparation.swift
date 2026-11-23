import Foundation
import SwiftData

/// Durable proof of an abandoned derivative cohort, retained with the draft
/// after editing resumes. An absent reservation is recorded distinctly.
struct SharedMediaCaptureAbortedPreparation: Codable, Equatable, Sendable {
    struct Member: Codable, Equatable, Sendable {
        let artifactID: UUID
        let mediaID: UUID
        let requestSHA256: String?
    }
    let attemptSHA256: String
    let planSHA256: String
    let members: [Member]

    func validate() throws {
        guard SharedMediaAcquisitionEncoding.isHash(attemptSHA256), SharedMediaAcquisitionEncoding.isHash(planSHA256),
              members.count <= 64, Set(members.map(\.artifactID)).count == members.count,
              Set(members.map(\.mediaID)).count == members.count,
              Set(members.map(\.artifactID)).isDisjoint(with: Set(members.map(\.mediaID))),
              members.allSatisfy({ $0.requestSHA256.map(SharedMediaAcquisitionEncoding.isHash) ?? true }) else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    @MainActor
    static func requireMembers(_ journal: SharedMediaCaptureDraftJournal, context: ModelContext) throws {
        for proof in journal.abortedPreparations ?? [] {
            for member in proof.members {
                let id = member.artifactID, mediaID = member.mediaID
                var query = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate {
                    $0.id == id || $0.mediaID == mediaID
                })
                query.fetchLimit = 2
                let rows = try context.fetch(query)
                guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
                guard let row = rows.first else {
                    guard member.requestSHA256 == nil else { throw SharedMediaStorageFailure.conflict }
                    continue
                }
                let artifact = try SharedMediaCaptureArtifactLedger.auditReceipt(row)
                guard artifact.request.scanID == journal.scanID,
                      artifact.request.submissionGeneration == journal.generation,
                      artifact.request.profile == journal.profile,
                      artifact.request.rootBindingSHA256 == journal.rootBindingSHA256,
                      artifact.request.id == id, artifact.request.mediaID == mediaID,
                      artifact.request.planSHA256 == proof.planSHA256,
                      try artifact.request.digest == member.requestSHA256,
                      artifact.retirement?.version == 2, artifact.retirement?.releasedRevision != nil,
                      artifact.retirement?.preparationSHA256 == proof.attemptSHA256 else {
                    throw SharedMediaStorageFailure.conflict
                }
            }
        }
    }

    @MainActor
    static func requireRetirement(_ artifact: SharedMediaCaptureArtifactLedger.Snapshot, context: ModelContext) throws {
        guard let retirement = artifact.retirement, retirement.version == 2,
              let saved = try SharedMediaCaptureDraftJournalReceipt.matching(scanID: artifact.request.scanID,
                generation: artifact.request.submissionGeneration, context: context),
              saved.value.profile == artifact.request.profile,
              saved.value.rootBindingSHA256 == artifact.request.rootBindingSHA256 else { throw SharedMediaStorageFailure.conflict }
        if saved.value.phase == .abortingPreparation,
           retirement.preparationSHA256 == (try saved.value.preparation?.digest) {
            try SharedMediaCapturePreparedAttempt.requireAbortMember(artifact.request,
                digest: retirement.preparationSHA256, context: context)
            return
        }
        guard retirement.releasedRevision != nil,
              let proof = saved.value.abortedPreparations?.first(where: { $0.attemptSHA256 == retirement.preparationSHA256 }),
              proof.planSHA256 == artifact.request.planSHA256,
              let member = proof.members.first(where: { $0.artifactID == artifact.request.id }),
              member.mediaID == artifact.request.mediaID, member.requestSHA256 == (try artifact.request.digest) else {
            throw SharedMediaStorageFailure.conflict
        }
    }
}
