import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ObservationAnalysisReviewReconciliationTests {
    typealias Store = ObservationAnalysisReviewPersistence
    let source = ObservationHistoryStateSyncTests()
    let projection = ObservationHistorySelectionSyncTests()
    let date = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func outgoingTargetAndCurrentSelectionSettleTogetherWithoutAuthorityLeakage() async throws {
        let (container, claim) = try await seeded(), before = try projection.caches(container)
        var calls = 0, finishes = 0
        let service = ObservationAnalysisReviewReconciliation(cloud: cloud(targetData: try targetData(), selectedData: try selectedData(),
            during: { calls = $0 }, finish: { finishes += 1 }), now: { date })
        let settled = try await service.reconcile(claim, container: container, isCurrent: { true })
        #expect(calls == 2 && finishes == 1 && settled.isComplete && settled.receipt == claim.intent.receipt)
        #expect(settled.observedAt == claim.intent.observedAt)
        let parent = try projection.parent(container)
        #expect(parent.selectedAnalysisID == selected.uuidString.lowercased() && parent.observationStateRevision == 12)
        #expect(parent.scientificName == "Danaus plexippus" && parent.localAIIdentificationReview.authority == nil)
        #expect(!parent.userConfirmedIdentification && parent.fieldNotes == "Preserved private note")
        #expect(try state(target, in: container).reviewRevision == 1 && state(selected, in: container).reviewRevision == 0)
        #expect(try state(target, in: container).observationStateRevision == 12)
        #expect(try projection.caches(container)[target.uuidString.lowercased()] == before[target.uuidString.lowercased()])
        let job = try #require(try ModelContext(container).fetchOfflineJob(id: Store.jobID(claim.intent.request.operationID, observationID: observation)))
        #expect(job.status == .complete && job.nextRunAt == nil)
        let replay = try Store.stage(claim.intent.request, ownerID: owner, container: container, isCurrent: { true },
                                    validateNew: { _ in throw Store.IntegrityError.conflict })
        #expect(try replay.storedData() == settled.storedData())
    }

    @Test func selectedTargetUsesOneReadAndLateUnchangedClaimCanSettle() async throws {
        let (container, claim) = try await seeded()
        var time = date, calls = 0
        let service = ObservationAnalysisReviewReconciliation(cloud: cloud(targetData: try targetData(selectedID: target), selectedData: Data(),
            during: { calls = $0; time = claim.expiresAt.addingTimeInterval(1) }), now: { time })
        let settled = try await service.reconcile(claim, container: container, isCurrent: { true })
        #expect(calls == 1 && settled.isComplete)
        #expect(try projection.parent(container).selectedAnalysisID == target.uuidString.lowercased())
        #expect(try projection.parent(container).localAIIdentificationReview.authority?.state == .aiRejected)
    }

    @Test func lateSecondReplyCanSettleTheUnchangedClaim() async throws {
        let (container, claim) = try await seeded()
        var time = date, calls = 0
        let service = ObservationAnalysisReviewReconciliation(cloud: cloud(targetData: try targetData(), selectedData: try selectedData(),
            during: { calls = $0; if $0 == 2 { time = claim.expiresAt.addingTimeInterval(1) } }), now: { time })
        let settled = try await service.reconcile(claim, container: container, isCurrent: { true })
        #expect(calls == 2 && settled.isComplete)
        #expect(try projection.parent(container).selectedAnalysisID == selected.uuidString.lowercased())
    }

    @Test func oldReceiptCannotOverwriteSelectionReturningToItsTarget() async throws {
        let (container, claim) = try await seeded()
        var calls = 0
        let service = ObservationAnalysisReviewReconciliation(cloud: cloud(targetData: try targetData(), selectedData: try selectedData(),
            during: { calls = $0 }), now: { date })
        _ = try await service.reconcile(claim, container: container, isCurrent: { true })
        _ = try await source.service(data: targetData(revision: 13, selectedID: target))
            .syncSelected(observationID: observation.uuidString, container: container)
        await #expect(throws: (any Error).self) { try await service.reconcile(claim, container: container, isCurrent: { true }) }
        #expect(calls == 2)
        #expect(try projection.parent(container).selectedAnalysisID == target.uuidString.lowercased())
        #expect(try projection.parent(container).observationStateRevision == 13)
    }

    @Test func accountLossInsideFinalTransactionRollsBackEveryWrite() async throws {
        let (container, claim) = try await seeded()
        var current = true, clockReads = 0
        let service = ObservationAnalysisReviewReconciliation(cloud: cloud(targetData: try targetData(), selectedData: try selectedData()), now: {
            clockReads += 1
            if clockReads == 3 { current = false }
            return date
        })
        await #expect(throws: (any Error).self) { try await service.reconcile(claim, container: container, isCurrent: { current }) }
        #expect(clockReads == 3)
        try requireUnchanged(container, claim: claim)
    }

    @Test(arguments: [false, true])
    func mismatchedPairNeverWritesEitherCacheOrCompletesJob(changedSelection: Bool) async throws {
        let (container, claim) = try await seeded()
        let second = try selectedData(revision: changedSelection ? 12 : 13, changedSelection: changedSelection)
        let service = ObservationAnalysisReviewReconciliation(cloud: cloud(targetData: try targetData(), selectedData: second), now: { date })
        await #expect(throws: (any Error).self) { try await service.reconcile(claim, container: container, isCurrent: { true }) }
        try requireUnchanged(container, claim: claim)
    }

    @Test(arguments: [false, true])
    func appliedReceiptFloorsOnlyItsOwnTargetAuthority(globalStale: Bool) async throws {
        let (container, claim) = try await seeded()
        let revision = globalStale ? 10 : 12
        let service = ObservationAnalysisReviewReconciliation(cloud: cloud(
            targetData: try targetData(revision: revision, review: globalStale ? 1 : 0), selectedData: try selectedData(revision: revision)), now: { date })
        await #expect(throws: (any Error).self) { try await service.reconcile(claim, container: container, isCurrent: { true }) }
        try requireUnchanged(container, claim: claim)
    }

    @Test(arguments: ["revision_conflict", "not_verified"])
    func negativeReceiptCanReconcileUnchangedCurrentAuthority(outcome: String) async throws {
        let (container, claim) = try await seeded(outcome: outcome)
        let service = ObservationAnalysisReviewReconciliation(cloud: cloud(targetData: try source.fixture(revision: 10), selectedData: Data()), now: { date })
        let settled = try await service.reconcile(claim, container: container, isCurrent: { true })
        #expect(settled.isComplete && settled.receipt == claim.intent.receipt)
        #expect(try projection.parent(container).observationStateRevision == 10)
    }

    @Test(arguments: [false, true])
    func failedTargetAdmissionOrSaveRollsBackSelectedProjectionAndReceipt(failSave: Bool) async throws {
        let (container, claim) = try await seeded()
        let service = ObservationAnalysisReviewReconciliation(cloud: cloud(targetData: try targetData(changedBytes: !failSave),
            selectedData: try selectedData()), now: { date }, save: { context in
                if failSave { throw Store.IntegrityError.unavailable }
                try context.save()
            })
        await #expect(throws: (any Error).self) { try await service.reconcile(claim, container: container, isCurrent: { true }) }
        try requireUnchanged(container, claim: claim)
    }

    @Test func selectedImportedResultNeverBorrowsOutgoingDisplay() async throws {
        let (container, claim) = try await seeded()
        let service = ObservationAnalysisReviewReconciliation(cloud: cloud(targetData: try targetData(),
            selectedData: try selectedData(imported: true)), now: { date })
        await #expect(throws: (any Error).self) { try await service.reconcile(claim, container: container, isCurrent: { true }) }
        try requireUnchanged(container, claim: claim)
    }

    @Test(arguments: [1, 2], ["account", "deletion", "baseline", "claim", "legacy", "selection", "sibling"])
    func eachAwaitRechecksOwnerDeletionBaselineAndClaim(atCall: Int, change: String) async throws {
        let (container, claim) = try await seeded()
        var current = true, calls = 0, finished = false
        let client = cloud(targetData: try targetData(), selectedData: try selectedData(), current: { current }, during: { number in
            calls = number
            guard number == atCall else { return }
            if change == "account" { current = false; return }
            if change == "claim" {
                _ = try Store.claim(claim.intent, at: claim.expiresAt, container: container, isCurrent: { true }); return
            }
            try source.update(container) { scan, context in
                switch change {
                case "deletion": try context.ensurePendingCloudDeletionTask(scanId: scan.id, requestingAccountID: owner, origin: .explicitUserDeletion)
                case "baseline": scan.commonName = "Later local display"
                case "legacy": context.insert(OfflineJobRecord(id: "legacy-review", kind: .identificationReviewSync, subjectId: scan.id))
                case "selection": context.insert(OfflineJobRecord(id: ObservationHistorySelectionIntent.jobID(scan.id), kind: .future, metadataJSON: "damaged"))
                default: context.insert(OfflineJobRecord(id: Store.jobID(UUID(), observationID: observation), kind: .future, metadataJSON: "damaged"))
                }
            }
        }, finish: { finished = true })
        let service = ObservationAnalysisReviewReconciliation(cloud: client, now: { date })
        await #expect(throws: (any Error).self) { try await service.reconcile(claim, container: container, isCurrent: { true }) }
        #expect(calls == atCall && finished)
        try requireUnchanged(container, claim: claim)
    }

    @Test func expiredClaimCannotBeginAnotherReadAndDoesNotLoseReceipt() async throws {
        let (container, claim) = try await seeded()
        var time = date, calls = 0
        let service = ObservationAnalysisReviewReconciliation(cloud: cloud(targetData: try targetData(), selectedData: try selectedData(),
            during: { calls = $0; time = claim.expiresAt }), now: { time })
        await #expect(throws: (any Error).self) { try await service.reconcile(claim, container: container, isCurrent: { true }) }
        #expect(calls == 1)
        try requireUnchanged(container, claim: claim)
    }

    @Test func callerGenerationLossAfterPairWithholdsProjection() async throws {
        let (container, claim) = try await seeded()
        var current = true
        let service = ObservationAnalysisReviewReconciliation(cloud: cloud(targetData: try targetData(), selectedData: try selectedData(),
            during: { if $0 == 2 { current = false } }), now: { date })
        await #expect(throws: (any Error).self) { try await service.reconcile(claim, container: container, isCurrent: { current }) }
        try requireUnchanged(container, claim: claim)
    }
}
