import Foundation
import SwiftData

/// These transitions participate in the parent's existing transaction. They
/// never save independently or publish a queue capability ahead of the parent.
@MainActor
enum SharedMediaCaptureDraftJournalSubmission {
    typealias Journal = SharedMediaCaptureDraftJournal
    typealias Receipt = SharedMediaCaptureDraftJournalReceipt

    static func reserve(plan: CaptureInitialEvidencePlan, input: SharedMediaCaptureSubmissionContext,
                        expected: Receipt.Snapshot?, context: ModelContext) throws {
        let current = try Receipt.matching(scanID: plan.scanID, generation: plan.generation, context: context)
        guard current != nil || expected != nil else { return }
        guard let current, current == expected, current.value.phase == .preparing,
              let preparation = current.value.preparation else {
            throw SharedMediaStorageFailure.stale
        }
        guard try preparation.plan(ownerID: plan.ownerID) == plan else { throw SharedMediaStorageFailure.conflict }
        let previous = current.value
        let next = Journal(format: previous.format, profile: previous.profile,
            rootBindingSHA256: previous.rootBindingSHA256, scanID: previous.scanID, generation: previous.generation,
            revision: try SharedMediaStoragePolicy.add(previous.revision, 1), phase: .submitting,
            sources: previous.sources, items: previous.items,
            frozenObservation: try .init(bytes: plan.encoded()), frozenContext: input, abortedPreparations: previous.abortedPreparations)
        try replace(current, with: next, context: context)
    }

    static func accept(_ submission: SharedMediaCaptureSubmission, context: ModelContext) throws {
        guard let current = try Receipt.matching(scanID: submission.scanID, generation: submission.generation,
            context: context) else { return }
        let previous = current.value
        guard previous.phase == .submitting, previous.profile == submission.profile,
              previous.rootBindingSHA256 == submission.rootBindingSHA256,
              previous.frozenObservation == submission.observation, previous.frozenContext == submission.context else {
            throw SharedMediaStorageFailure.conflict
        }
        let next = Journal(format: previous.format, profile: previous.profile,
            rootBindingSHA256: previous.rootBindingSHA256, scanID: previous.scanID, generation: previous.generation,
            revision: try SharedMediaStoragePolicy.add(previous.revision, 1), phase: .accepted,
            sources: previous.sources, items: previous.items,
            frozenObservation: previous.frozenObservation, frozenContext: previous.frozenContext, abortedPreparations: previous.abortedPreparations)
        try replace(current, with: next, context: context)
    }

    private static func replace(_ current: Receipt.Snapshot, with next: Journal, context: ModelContext) throws {
        let generation = current.value.generation
        var query = FetchDescriptor<SharedMediaCaptureDraftJournalRecord>(predicate: #Predicate { $0.id == generation })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first, try Receipt.decode(row) == current else {
            throw SharedMediaStorageFailure.stale
        }
        let bytes = try next.encoded()
        row.revision = next.revision; row.bodyData = bytes
        row.bodySHA256 = SharedMediaAcquisitionEncoding.digest(bytes)
    }
}
