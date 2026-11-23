import Foundation
import SwiftData

/// One atomic ordinary submission under the registered original owner and the
/// scan persistence lock. It neither claims funding nor starts remote work.
@MainActor
final class SharedMediaOrdinaryAcceptanceOperations {
    typealias Rows = SharedMediaNativeAppOriginalRows
    private let container: ModelContainer
    private let authority: SharedMediaNativeAppOperationAuthority
    private let io: SharedMediaNativeOriginalIO
    private let binding: SharedMediaNativeBinding
    private let files: PhotoPreparationLockedFiles
    private let availableBytes: () throws -> Int64
    private let boundary: (SharedMediaNativeLifecycleBoundary) throws -> Void
    private var consumed = false

    init(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
         io: SharedMediaNativeOriginalIO, binding: SharedMediaNativeBinding, files: PhotoPreparationLockedFiles,
         availableBytes: @escaping () throws -> Int64,
         boundary: @escaping (SharedMediaNativeLifecycleBoundary) throws -> Void) {
        self.container = container; self.authority = authority; self.io = io; self.binding = binding
        self.files = files; self.availableBytes = availableBytes; self.boundary = boundary
    }

    private struct Before {
        let header: SharedMediaNativeAppEligibility.Header
        let facts: SharedMediaNativeAppMetadataFacts
        let originals: [UUID: SharedMediaNativeOriginalAccounting.Snapshot]
        let pairs: [SharedMediaNativePairFileState]
        let budget: SharedMediaNativeAcquisitionBudget.Snapshot
    }

    func accept(_ admission: SharedMediaOrdinaryQueueAdmission,
                holds: SharedMediaOrdinaryHoldCohort) async throws -> SharedMediaOrdinarySubmissionAcceptance {
        guard !consumed, admission.submission.profile == authority.profile else { throw SharedMediaStorageFailure.closed }
        try admission.submission.validate(holds: holds)
        _ = try authority.header(container)
        // An old writer epoch may describe an exact saved acknowledgement. It
        // cannot create a fresh transaction under a new owner's registration.
        if let saved = try replay(admission, holds: holds) { return saved }
        guard admission.submission.writerEpoch == authority.writerEpoch else { throw SharedMediaStorageFailure.stale }
        let before = try predecessor(admission, holds: holds)
        var originalSeals: [SharedMediaPhotoRetirementInspection] = []
        var pairSeals: [SharedMediaNativePairCompletion] = []
        for request in holds.requests {
            guard let original = before.originals[request.source.assetID] else { throw SharedMediaStorageFailure.conflict }
            let seal = try await io.inspect(original.file)
            guard seal.identity == request.completion.descriptor, seal.binding == binding.bytes,
                  seal.epoch == binding.epoch else { throw SharedMediaStorageFailure.conflict }
            originalSeals.append(seal)
        }
        for pair in before.pairs {
            let intent = try pair.intent()
            for id in [intent.ai.id, intent.display.id] { pairSeals.append(try await io.inspectCompletedPair(pair, workID: id)) }
        }
        let current = try predecessor(admission, holds: holds)
        guard current.header == before.header, current.facts == before.facts,
              current.originals == before.originals, current.budget.totals == before.budget.totals else {
            throw SharedMediaStorageFailure.stale
        }
        let context = fresh()
        do {
            let rows = try SharedMediaOrdinaryAcceptanceRows(context: context, admission: admission, holds: holds)
            var projected = before.budget.totals
            try projected.includePhotoPhysical(materialized: rows.metadataBytes, reserved: 0)
            // Existing originals are already charged. Only new envelopes and
            // queue metadata require additional free space at this boundary.
            let extra = try SharedMediaStoragePolicy.add(rows.metadataBytes, Int64(admission.metadata.json.utf8.count))
            try projected.checkAvailable(availableBytes(), additionalReservation: extra)
            try boundary(.beforeSave)
            try rows.validate(context)
            guard try authority.header(container) == before.header else { throw SharedMediaStorageFailure.stale }
            // A distinct clean context must still see the exact predecessor;
            // the invocation-local ordinary inspection has already closed.
            let final = try predecessor(admission, holds: holds)
            guard final.header == before.header, final.facts == before.facts,
                  final.originals == before.originals, final.budget.totals == before.budget.totals else {
                throw SharedMediaStorageFailure.stale
            }
            for seal in originalSeals { try files.requireCurrentSharedInspection(seal) }
            for seal in pairSeals { try files.requireCurrentPairCompletion(seal, binding: binding) }
            consumed = true
            do {
                try context.save()
                try boundary(.afterSave)
                try acknowledge(rows, before: before, totals: projected)
            } catch {
                let failure = error
                context.rollback()
                // A thrown save/acknowledgement is not proof of absence. Only
                // exact independent readback can turn uncertainty into success.
                do { try acknowledge(rows, before: before, totals: projected) } catch { throw failure }
            }
            return rows.acceptance
        } catch {
            context.rollback()
            throw error
        }
    }

    private func predecessor(_ admission: SharedMediaOrdinaryQueueAdmission,
                             holds: SharedMediaOrdinaryHoldCohort) throws -> Before {
        let header = try authority.header(container)
        func check() throws { guard try authority.header(container) == header else { throw SharedMediaStorageFailure.stale } }
        return try SharedMediaOrdinaryInspection.withVerifiedRead(container: container, profile: authority.profile,
            checkpoint: check) { inspection in
            let context = self.fresh()
            try admission.requireAbsent(in: context)
            guard try SharedMediaOrdinarySubmissionReceipt.existing(admission.submission, in: context) == nil else {
                throw SharedMediaStorageFailure.conflict
            }
            try SharedMediaNativeReleaseStageIdentity.requireFresh(
                holds.requests.map(\.id) + [admission.submission.scanID, admission.submission.generation, admission.submission.eventID],
                inventoryID: self.authority.profile.inventoryID, context: context)
            let facts = try SharedMediaNativeAppMetadataFacts.capture(context, profile: self.authority.profile)
            var originals: [UUID: SharedMediaNativeOriginalAccounting.Snapshot] = [:]
            for request in holds.requests {
                try facts.requireMutable(request.source.packageID)
                let rows = try Rows(context, profile: self.authority.profile, source: request.source)
                try rows.readyPackage(request.source, facts: facts)
                _ = try Rows.reference(context, source: request.source, live: true)
                let original = try inspection?.original(request.source.assetID, inventoryID: self.authority.profile.inventoryID,
                    context: context, checkpoint: check) ?? SharedMediaNativeOriginalAccounting.audit(
                        assetID: request.source.assetID, inventoryID: self.authority.profile.inventoryID, context: context, checkpoint: check)
                let completed = try rows.completed()
                guard request.inventoryRevision == header.inventory.revision,
                      request.sourcePackageRevision == rows.package.revision, request.sourceMembershipRevision == rows.member.revision,
                      request.acquisition == completed.0, request.completion == completed.1,
                      request.liveCount == original.liveCount, request.countRevision == original.countRevision,
                      original.retirement == nil else { throw SharedMediaStorageFailure.stale }
                originals[request.source.assetID] = original
            }
            guard let first = holds.requests.first else { throw SharedMediaStorageFailure.conflict }
            let rows = try Rows(context, profile: self.authority.profile, source: first.source)
            let pairs = try SharedMediaNativeReadyPhotoCohort.read(admission.submission.observation,
                package: rows.package, member: rows.member, inventory: rows.inventory, context: context)
            let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context,
                inventory: rows.inventory, ownerID: self.authority.profile.ownerID, format: .appV2,
                ordinary: inspection, checkpoint: check)
            try check()
            return Before(header: header, facts: facts, originals: originals, pairs: pairs, budget: budget)
        }
    }

    private func replay(_ admission: SharedMediaOrdinaryQueueAdmission,
                        holds: SharedMediaOrdinaryHoldCohort) throws -> SharedMediaOrdinarySubmissionAcceptance? {
        let context = fresh()
        guard let saved = try SharedMediaOrdinarySubmissionReceipt.existing(admission.submission, in: context) else { return nil }
        guard saved.holds == holds, case .accepted(let acceptance) = saved.state else { throw SharedMediaStorageFailure.conflict }
        try admission.requireSaved(in: context)
        _ = try SharedMediaOrdinaryStoreAudit.verify(context: context, profile: authority.profile)
        return acceptance
    }

    private func acknowledge(_ rows: SharedMediaOrdinaryAcceptanceRows, before: Before,
                             totals: SharedMediaStoragePolicy.Totals) throws {
        try boundary(.beforeReadback)
        let expected = try SharedMediaNativeAppMetadataFacts.successor(before.header)
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        let context = fresh()
        guard try SharedMediaNativeAppMetadataFacts.capture(context, profile: authority.profile) == before.facts,
              let receipt = try SharedMediaOrdinarySubmissionReceipt.existing(rows.admission.submission, in: context),
              receipt.holds == rows.holds, receipt.state == .accepted(rows.acceptance),
              receipt.metadataBytes == rows.metadataBytes else { throw SharedMediaStorageFailure.conflict }
        try rows.admission.requireSaved(in: context)
        _ = try SharedMediaOrdinaryStoreAudit.verify(context: context, profile: authority.profile)
        for (id, original) in before.originals {
            let count = Int64(rows.holds.requests.filter { $0.source.assetID == id }.count)
            let expected = try original.atInventoryRevision(rows.acceptance.inventoryRevision,
                liveCount: SharedMediaStoragePolicy.add(original.liveCount, count),
                countRevision: SharedMediaStoragePolicy.add(original.countRevision, 1), retirement: nil)
            guard try SharedMediaNativeOriginalAccounting.auditAcceptedOrdinary(assetID: id,
                inventoryID: authority.profile.inventoryID, context: context) == expected else { throw SharedMediaStorageFailure.conflict }
        }
        let actual = try SharedMediaOrdinaryInspection.withVerifiedRead(container: container, profile: authority.profile,
            checkpoint: { guard try self.authority.header(self.container) == expected else { throw SharedMediaStorageFailure.stale } }) { inspection in
            let id = self.authority.profile.inventoryID
            let inventory = try Rows.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
            return try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
                ownerID: self.authority.profile.ownerID, format: .appV2, ordinary: inspection).totals
        }
        guard actual == totals else { throw SharedMediaStorageFailure.conflict }
    }

    private func fresh() -> ModelContext {
        let context = ModelContext(container); context.autosaveEnabled = false; return context
    }
}
