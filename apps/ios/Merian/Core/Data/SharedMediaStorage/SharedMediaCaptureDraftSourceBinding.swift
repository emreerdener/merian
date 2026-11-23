import Foundation
import SwiftData

/// Final-plan binding consumes exact ready source membership, not a copy of the
/// source file. The caller holds the complete physical/account audit while the
/// parent and its final ordered membership are committed atomically.
@MainActor
enum SharedMediaCaptureDraftSourceBinding {
    struct Result {
        let artifactIDs: [UUID]
        let sources: [SharedMediaCaptureArtifactLedger.Snapshot]
        var packageBytes: Int64 {
            get throws {
                try sources.reduce(0) { try SharedMediaStoragePolicy.add($0,
                    SharedMediaCaptureBudget.unboundPackageBytes($1.request)) }
            }
        }
    }

    static func read(plan: CaptureInitialEvidencePlan, profile: SharedMediaNativeAppProfile,
                     rootBindingSHA256: String, context: ModelContext) throws -> Result {
        let scan = plan.scanID, generation = plan.generation
        let query = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate {
            $0.recipientScanID == scan || $0.submissionGeneration == generation
        })
        let rows = try SharedMediaCaptureArtifactCohort.activeRows(query, context: context) { value in
            guard value.request.profile == profile, value.request.scanID == scan,
                  value.request.submissionGeneration == generation,
                  value.request.rootBindingSHA256 == rootBindingSHA256 else { throw SharedMediaStorageFailure.conflict }
        }
        if rows.isEmpty { return .init(artifactIDs: plan.uploads.map { _ in UUID() }, sources: []) }
        let sources = try rows.map(SharedMediaCaptureArtifactLedger.receipt)
        var mapped: [UUID: SharedMediaCaptureArtifactLedger.Snapshot] = [:]
        let journal = try SharedMediaCaptureDraftJournalReceipt.matching(scanID: scan, generation: generation, context: context)
        let preparation = journal?.value.phase == .preparing ? journal?.value.preparation : nil
        if let preparation {
            guard try preparation.plan(ownerID: profile.ownerID) == plan else { throw SharedMediaStorageFailure.conflict }
        }
        for source in sources {
            let request = source.request
            let input = try plan.artifactInput(mediaID: request.mediaID, id: request.id)
            if request.format == .v1 {
                guard preparation != nil, input.matches(request) else { throw SharedMediaStorageFailure.conflict }
                try SharedMediaCapturePreparedAttempt.requireMember(request, context: context)
            } else if !input.bindsSource(request) { throw SharedMediaStorageFailure.conflict }
            guard source.phase == .ready, source.remoteStage == nil,
                  request.profile == profile, request.rootBindingSHA256 == rootBindingSHA256,
                  mapped.updateValue(source, forKey: request.mediaID) == nil else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        let sourceRoles: Set<String> = ["source_image", "source_audio", "source_video", "source_companion_audio"]
        let expected = Set(plan.uploads.filter { preparation != nil || sourceRoles.contains($0.role.rawValue) }.map { $0.artifact.mediaID })
        guard Set(mapped.keys) == expected else { throw SharedMediaStorageFailure.conflict }
        return .init(artifactIDs: plan.uploads.map { mapped[$0.artifact.mediaID]?.request.id ?? UUID() }, sources: sources)
    }

    static func newPhysicalReservation(_ value: SharedMediaCaptureSubmission, sourceIDs: Set<UUID>) throws -> Int64 {
        var bytes = Int64(try value.encoded().count + 64 + SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes + 64)
        for member in value.members where !sourceIDs.contains(member.artifactID) {
            let input = try value.artifact(mediaID: member.mediaID)
            let headroom = Int64(2 * SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes + 128 + 160
                + SharedMediaCaptureRemoteStage.maximumBytes + 64)
            bytes = try SharedMediaStoragePolicy.add(bytes, SharedMediaStoragePolicy.add(input.byteCount, headroom))
        }
        return bytes
    }

    static func requireUnclaimed(scan: UUID, context: ModelContext) throws {
        let lower = scan.uuidString.lowercased(), upper = scan.uuidString
        let job = OfflineQueueManager.scanIngestionJobId(scanId: lower)
        let upperJob = OfflineQueueManager.scanIngestionJobId(scanId: upper)
        try absent(context, FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == lower || $0.id == upper }))
        try absent(context, FetchDescriptor<OfflineJobRecord>(predicate: #Predicate {
            $0.id == job || $0.id == upperJob || $0.subjectId == lower || $0.subjectId == upper
        }))
        try absent(context, FetchDescriptor<OfflineQueueEvent>(predicate: #Predicate {
            $0.scanId == lower || $0.scanId == upper || $0.jobId == job || $0.jobId == upperJob
        }))
        try absent(context, FetchDescriptor<ActiveOfflineQueuedScanGoalHint>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper }))
        try absent(context, FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper }))
        try absent(context, FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.observationID == lower || $0.observationID == upper }))
        try absent(context, FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper }))
    }

    private static func absent<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws {
        var query = descriptor; query.fetchLimit = 1
        guard try context.fetch(query).isEmpty else { throw SharedMediaStorageFailure.conflict }
    }
}
