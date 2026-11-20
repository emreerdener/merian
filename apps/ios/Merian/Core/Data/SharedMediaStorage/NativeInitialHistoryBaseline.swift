import Foundation
import SwiftData

/// Historical enrollment identity only. No selection or media ownership grant.
struct NativeHistoryAssociation: Codable, Equatable, Sendable {
    let ownerID: UUID, observationID: UUID, baselineAnalysisID: UUID
    let intentID: UUID?
    let provenance: ObservationHistoryEnrollmentIntent.BaselineProvenance?
    let snapshotSHA256: String

    init(_ value: ObservationHistoryEnrollmentIntent.BaselineAssociation) throws {
        ownerID = value.ownerID; observationID = value.observationID; intentID = value.intentID
        provenance = value.provenance
        baselineAnalysisID = value.baselineAnalysisID; snapshotSHA256 = value.snapshotSHA256
        try validate()
    }

    func validate() throws {
        guard baselineAnalysisID != ownerID, baselineAnalysisID != observationID,
              (intentID != nil && provenance == nil) || (intentID == nil && provenance == .serverRecovery),
              SharedMediaAcquisitionEncoding.isHash(snapshotSHA256) else { throw SharedMediaStorageFailure.conflict }
        _ = try SharedMediaAcquisitionEncoding.encode(self, maximum: 512)
    }
}

@MainActor
enum NativeInitialHistoryBaseline {
    struct Value {
        let association: NativeHistoryAssociation
        let result: ObservationHistoryPage.Result
    }

    /// The durable server receipt supplies identity; never the selected ID or
    /// an inferred first analysis. Missing legacy association remains held.
    static func read(_ prepared: SharedMediaNativeReceivingIntent.Prepared, context: ModelContext) throws -> Value? {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.closed }
        let observation = prepared.observationID, owner = prepared.profile.ownerID
        let lower = observation.uuidString.lowercased(), upper = observation.uuidString
        try requireNoDeletion(prepared, context: context)
        guard let saved = try ObservationHistoryEnrollmentIntent.baseline(observationID: observation,
            ownerID: owner, context: context) else { return nil }
        guard try !ObservationHistoryEnrollmentIntent.holds(lower, context: context) else { throw SharedMediaStorageFailure.closed }
        let scan = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper }))
        guard scan.id == lower, scan.analysisOwnerAccountID == owner.uuidString.lowercased(),
              scan.analysisSelectionInitialized, scan.selectedAnalysisID.flatMap(UUID.init(uuidString:)) != nil,
              let revision = scan.observationStateRevision, revision >= 0 else { throw SharedMediaStorageFailure.conflict }
        let id = saved.baselineAnalysisID.uuidString.lowercased(), alias = saved.baselineAnalysisID.uuidString
        let child = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == id || $0.id == alias }))
        guard child.id == id, child.observationID == lower, child.ownerAccountID == owner.uuidString.lowercased(),
              child.snapshotVersion == 3, child.completedAt == nil,
              ObservationHistoryEnrollmentIntent.baselineDigest(child.resultSnapshotData) == saved.snapshotSHA256 else {
            throw SharedMediaStorageFailure.conflict
        }
        let result = try ObservationHistoryPage.snapshot(child.resultSnapshotData, observationID: lower, ordinal: 1)
        guard result.version == 3, result.analysisID == saved.baselineAnalysisID else { throw SharedMediaStorageFailure.conflict }
        return try .init(association: .init(saved), result: result)
    }

    static func requireNoDeletion(_ prepared: SharedMediaNativeReceivingIntent.Prepared, context: ModelContext) throws {
        let lower = prepared.observationID.uuidString.lowercased(), upper = prepared.observationID.uuidString
        var query = FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper })
        query.fetchLimit = 1
        guard try context.fetch(query).isEmpty else { throw SharedMediaStorageFailure.conflict }
    }
}

/// Exact existing enrollment recovery only. No Applied witness or native grant.
struct NativeInitialEnrollmentRecovery: Equatable, Sendable {
    let candidate: SharedMediaNativeReceivedCandidate
    let prepared: SharedMediaNativeReceivingIntent.Prepared
    let intent: ObservationHistoryEnrollmentIntent.Receipt
    let originalRowSHA256: String
    let cohortSHA256: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.candidate == rhs.candidate, lhs.intent == rhs.intent,
              lhs.originalRowSHA256 == rhs.originalRowSHA256, lhs.cohortSHA256 == rhs.cohortSHA256,
              let left = try? lhs.prepared.encoded(), let right = try? rhs.prepared.encoded() else { return false }
        return left == right
    }
}
