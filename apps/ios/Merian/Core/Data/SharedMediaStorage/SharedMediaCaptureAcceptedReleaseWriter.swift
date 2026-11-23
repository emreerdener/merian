import Foundation
import SwiftData

enum SharedMediaCaptureReleaseBoundary: CaseIterable, Sendable {
    case beforeIntentSave, afterIntentSave, beforeMemberIntentSave, afterMemberIntentSave
    case beforeUnlink, afterUnlink, beforeMemberReleaseSave, afterMemberReleaseSave
    case beforeFinalSave, afterFinalSave
}

/// The registered owner holds scan/account/root ownership for the whole call.
/// The durable parent intent is the sole continuation authority after the first
/// save; neither a selected result nor an upload acknowledgement can replace it.
@MainActor
enum SharedMediaCaptureAcceptedReleaseWriter {
    typealias Snapshot = SharedMediaCaptureSubmissionReceipt.Snapshot
    typealias Boundary = (SharedMediaCaptureReleaseBoundary) throws -> Void

    static func release(scanID: UUID, generation: UUID, container: ModelContainer,
                        authority: SharedMediaNativeAppOperationAuthority, files: SharedMediaCaptureArtifactFiles,
                        availableBytes: () throws -> Int64, boundary: Boundary = { _ in }) async throws -> SharedMediaCaptureAcceptedRelease {
        let before = try authority.header(container)
        let totals = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        var saved = try current(scanID: scanID, generation: generation, container: container, authority: authority, files: files)
        if saved.release == nil {
            let reservation = Int64(SharedMediaCaptureAcceptedRelease.maximumBytes + 64)
                + Int64(saved.artifacts.count * (SharedMediaCaptureMemberRelease.maximumBytes + 64))
            try totals.checkAvailable(availableBytes(), additionalReservation: reservation)
            try ConfirmedSpeciesReviewPersistence.transaction {
                try files.check()
                guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
                let context = ModelContext(container); context.autosaveEnabled = false
                guard try SharedMediaCaptureSubmissionReceipt.read(parent(saved.submission, context: context), in: context) == saved else {
                    throw SharedMediaStorageFailure.stale
                }
                let proof = try SharedMediaCaptureReleaseQualification.read(saved, context: context)
                let intent = try SharedMediaCaptureAcceptedRelease(proof: proof, saved: saved,
                    inventoryRevision: SharedMediaStoragePolicy.add(before.inventory.revision, 1))
                try persistParent(saved, release: intent, context: context, authority: authority, files: files, boundary: boundary)
            }
            saved = try current(scanID: scanID, generation: generation, container: container, authority: authority, files: files)
        }
        guard let initial = saved.release else { throw SharedMediaStorageFailure.conflict }
        for id in initial.members.map(\.artifactID) {
            try Task.checkCancellation()
            _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
            saved = try current(scanID: scanID, generation: generation, container: container, authority: authority, files: files)
            guard let intent = saved.release, try intent.intentSHA256 == initial.intentSHA256,
                  let artifact = saved.artifacts.first(where: { $0.request.id == id }) else { throw SharedMediaStorageFailure.stale }
            if artifact.acceptedRelease == nil {
                guard intent.releasedRevision == nil, let member = intent.members.first(where: { $0.artifactID == id }) else {
                    throw SharedMediaStorageFailure.conflict
                }
                let header = try authority.header(container)
                let child = try SharedMediaCaptureMemberRelease(format: .v1, parentIntentSHA256: intent.intentSHA256,
                    member: member, inventoryRevision: SharedMediaStoragePolicy.add(header.inventory.revision, 1), releasedRevision: nil)
                try SharedMediaCaptureReleasePersistence.member(artifact, release: child, parent: saved,
                    container: container, authority: authority, files: files, boundary: boundary)
                saved = try current(scanID: scanID, generation: generation, container: container, authority: authority, files: files)
            }
            guard let held = saved.artifacts.first(where: { $0.request.id == id }), var child = held.acceptedRelease else {
                throw SharedMediaStorageFailure.conflict
            }
            if child.releasedRevision == nil {
                try boundary(.beforeUnlink)
                guard try current(scanID: scanID, generation: generation, container: container, authority: authority, files: files) == saved else {
                    throw SharedMediaStorageFailure.stale
                }
                try files.unlinkAcceptedArtifact(held)
                try boundary(.afterUnlink)
                child.releasedRevision = try SharedMediaStoragePolicy.add(authority.header(container).inventory.revision, 1)
                try SharedMediaCaptureReleasePersistence.member(held, release: child, parent: saved,
                    container: container, authority: authority, files: files, boundary: boundary)
            }
        }
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        saved = try current(scanID: scanID, generation: generation, container: container, authority: authority, files: files)
        guard var release = saved.release, try release.intentSHA256 == initial.intentSHA256 else { throw SharedMediaStorageFailure.stale }
        if release.releasedRevision == nil {
            guard saved.artifacts.allSatisfy({ $0.acceptedRelease?.releasedRevision != nil }) else { throw SharedMediaStorageFailure.closed }
            release.releasedRevision = try SharedMediaStoragePolicy.add(authority.header(container).inventory.revision, 1)
            let context = ModelContext(container); context.autosaveEnabled = false
            try persistParent(saved, release: release, context: context, authority: authority, files: files, boundary: boundary)
        }
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        let finished = try current(scanID: scanID, generation: generation, container: container, authority: authority, files: files)
        guard finished.release == release else { throw SharedMediaStorageFailure.stale }
        return release
    }

    static func current(scanID: UUID, generation: UUID, container: ModelContainer,
                        authority: SharedMediaNativeAppOperationAuthority, files: SharedMediaCaptureArtifactFiles) throws -> Snapshot {
        _ = try authority.header(container); try files.check()
        let context = ModelContext(container); context.autosaveEnabled = false
        let saved = try SharedMediaCaptureCompletedCustody.read(scanID: scanID, generation: generation,
            ownerID: authority.profile.ownerID, context: context)
        guard saved.submission.profile == authority.profile, saved.submission.rootBindingSHA256 == files.rootBindingSHA256,
              case .accepted = saved.state else { throw SharedMediaStorageFailure.closed }
        return saved
    }

    private static func persistParent(_ saved: Snapshot, release: SharedMediaCaptureAcceptedRelease,
                                      context: ModelContext, authority: SharedMediaNativeAppOperationAuthority,
                                      files: SharedMediaCaptureArtifactFiles, boundary: Boundary) throws {
        let before = try authority.header(context.container), row = try parent(saved.submission, context: context)
        guard try SharedMediaCaptureSubmissionReceipt.auditRead(row, in: context) == saved,
              case let .accepted(acceptance) = saved.state else { throw SharedMediaStorageFailure.stale }
        let released = release.releasedRevision != nil, revision = release.releasedRevision ?? release.inventoryRevision
        guard released == (saved.release != nil), revision == (try SharedMediaStoragePolicy.add(before.inventory.revision, 1)) else {
            throw SharedMediaStorageFailure.conflict
        }
        if let prior = saved.release {
            guard prior.releasedRevision == nil, try prior.intentSHA256 == release.intentSHA256,
                  saved.artifacts.allSatisfy({ $0.acceptedRelease?.releasedRevision != nil }) else { throw SharedMediaStorageFailure.conflict }
        }
        if saved.release == nil {
            guard try SharedMediaCaptureReleaseQualification.read(saved, context: context) == release.proof else {
                throw SharedMediaStorageFailure.stale
            }
        }
        let inventoryID = saved.submission.profile.inventoryID
        let inventory = try SharedMediaCaptureReleasePersistence.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let encoded = try release.encoded(submission: saved.submission, acceptance: acceptance, artifacts: saved.artifacts)
        guard let requestData = row.requestData, let acceptanceData = row.acceptanceData else { throw SharedMediaStorageFailure.conflict }
        let requestBytes = Int64(requestData.count + 64)
        let acceptanceBytes = Int64(acceptanceData.count + 64)
        let replacementBytes = try SharedMediaStoragePolicy.add(
            SharedMediaStoragePolicy.add(requestBytes, acceptanceBytes), Int64(encoded.count + 64))
        guard replacementBytes <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
        row.retirementData = encoded
        row.retirementSHA256 = row.retirementData.map(SharedMediaAcquisitionEncoding.digest)
        row.phaseRaw = released ? "acceptedReleased" : "acceptedRetiring"
        row.revision = released ? 3 : 2
        inventory.revision = revision
        try boundary(released ? .beforeFinalSave : .beforeIntentSave)
        try files.check()
        guard try authority.header(context.container) == before else { throw SharedMediaStorageFailure.stale }
        try context.save()
        try boundary(released ? .afterFinalSave : .afterIntentSave)
        _ = try authority.header(context.container); try files.check()
    }

    private static func parent(_ submission: SharedMediaCaptureSubmission, context: ModelContext) throws -> SharedMediaOrdinarySubmissionRecord {
        let scan = submission.scanID, generation = submission.generation
        return try SharedMediaCaptureReleasePersistence.one(context,
            FetchDescriptor<SharedMediaOrdinarySubmissionRecord>(predicate: #Predicate {
                $0.recipientScanID == scan || $0.submissionGeneration == generation || $0.id == generation
            }))
    }
}
