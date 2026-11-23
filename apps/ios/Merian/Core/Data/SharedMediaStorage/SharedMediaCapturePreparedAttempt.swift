import Foundation
import SwiftData

/// Local preparation identity, without queue, funding, or provider authority.
/// The final artifact files are retained here before the immutable submission
/// binds them. A partial attempt never substitutes newly rendered bytes.
struct SharedMediaCapturePreparedAttempt: Codable, Equatable, Sendable {
    let version: Int
    let previousJournalSHA256: String
    let observation: SharedMediaNativePreparationBlob
    let artifactIDs: [UUID]

    var digest: String {
        get throws {
            try SharedMediaAcquisitionEncoding.digest(SharedMediaAcquisitionEncoding.encode(self,
                maximum: SharedMediaCaptureDraftJournal.maximumBytes))
        }
    }

    init(plan: CaptureInitialEvidencePlan, journal: SharedMediaCaptureDraftJournalReceipt.Snapshot) throws {
        version = 1; previousJournalSHA256 = journal.sha256
        observation = try .init(bytes: plan.encoded())
        artifactIDs = plan.uploads.map { upload in
            journal.value.sources.first(where: { $0.input.mediaID == upload.artifact.mediaID })?.input.id ?? UUID()
        }
        try validate(journal: journal.value)
    }

    func plan(ownerID: UUID) throws -> CaptureInitialEvidencePlan {
        try observation.validate()
        return try .init(ownerID: ownerID, data: observation.bytes)
    }

    func validate(journal: SharedMediaCaptureDraftJournal) throws {
        let plan = try plan(ownerID: journal.profile.ownerID)
        guard version == 1, SharedMediaAcquisitionEncoding.isHash(previousJournalSHA256),
              plan.scanID == journal.scanID, plan.generation == journal.generation,
              artifactIDs.count == plan.uploads.count, Set(artifactIDs).count == artifactIDs.count else {
            throw SharedMediaStorageFailure.conflict
        }
        try journal.requirePlan(plan)
        let retiredIDs = (journal.abortedPreparations ?? []).flatMap { $0.members.flatMap { [$0.artifactID, $0.mediaID] } }
        guard Set(plan.uploads.map(\.artifact.mediaID)).isDisjoint(with: Set(retiredIDs)) else { throw SharedMediaStorageFailure.conflict }
        let reservedIDs = Set([journal.profile.ownerID, journal.profile.inventoryID, journal.profile.generation,
            journal.scanID, journal.generation] + journal.items.map(\.id) + plan.uploads.map(\.artifact.mediaID) + retiredIDs)
        guard Set(artifactIDs).isDisjoint(with: reservedIDs) else { throw SharedMediaStorageFailure.conflict }
        for (upload, id) in zip(plan.uploads, artifactIDs) {
            if let source = journal.sources.first(where: { $0.input.mediaID == upload.artifact.mediaID }) {
                guard id == source.input.id else { throw SharedMediaStorageFailure.conflict }
            } else if journal.sources.contains(where: { $0.input.id == id }) { throw SharedMediaStorageFailure.conflict }
        }
    }

    func input(mediaID: UUID, ownerID: UUID) throws -> SharedMediaCaptureArtifactInput {
        let plan = try plan(ownerID: ownerID)
        guard let index = plan.uploads.firstIndex(where: { $0.artifact.mediaID == mediaID }),
              artifactIDs.indices.contains(index) else { throw SharedMediaStorageFailure.conflict }
        return try plan.artifactInput(mediaID: mediaID, id: artifactIDs[index])
    }

    @MainActor
    static func requireMember(_ request: SharedMediaCaptureArtifactRequest, context: ModelContext,
                              phases: Set<SharedMediaCaptureDraftJournal.Phase> = [.preparing]) throws {
        guard let saved = try SharedMediaCaptureDraftJournalReceipt.matching(scanID: request.scanID,
            generation: request.submissionGeneration, context: context), phases.contains(saved.value.phase),
              saved.value.profile == request.profile, saved.value.rootBindingSHA256 == request.rootBindingSHA256,
              let attempt = saved.value.preparation,
              try attempt.input(mediaID: request.mediaID, ownerID: request.profile.ownerID).matches(request) else {
            throw SharedMediaStorageFailure.conflict
        }
        try SharedMediaCaptureDraftSourceBinding.requireUnclaimed(scan: request.scanID, context: context)
    }

    @MainActor
    static func requireAbortMember(_ request: SharedMediaCaptureArtifactRequest, digest: String?, context: ModelContext) throws {
        guard request.format == .v1,
              !request.role.rawValue.hasPrefix("source_"),
              let saved = try SharedMediaCaptureDraftJournalReceipt.matching(scanID: request.scanID,
                generation: request.submissionGeneration, context: context),
              let attempt = saved.value.preparation, digest == (try attempt.digest) else {
            throw SharedMediaStorageFailure.closed
        }
        try requireMember(request, context: context, phases: [.abortingPreparation])
    }
}
