import CryptoKit
import Foundation
import SwiftData

/// Evidence from one validated ordinary response, frozen before persistence.
/// It confers no review or media authority. Only the first-insert writer may
/// retain it, and only first enrollment may compare the retained proof.
struct OrdinaryInferenceCompletion: Sendable {
    let scanID: String
    let generation: UUID
    let account: InferenceCompletionAccountScope
    private let resultSHA256: String
    private let projection: Projection

    static let metadataKey = "original_inference_completion_v1"
    static let maximumBytes = 1_048_576
    enum Invalid: Error { case evidence }

    struct Projection: Codable, Equatable, Sendable {
        let confidence: Double?
        let biological: Bool
        let reasoning: String?
        let tier: String?
        let primary: Data?
        let provenance: Data?
        let candidates: Data?
        let pet: Data?

        init(_ data: SpeciesData) throws {
            confidence = data.confidenceScore
            biological = data.isBiological
            reasoning = data.aiReasoning
            tier = data.inferenceTier
            primary = try Self.json(data.primaryIdentification?.data)
            provenance = try Self.json(data.identificationProvenance?.data)
            candidates = try Self.json(data.candidates.map { try JSONEncoder().encode($0) })
            pet = try Self.json(data.petIdentification.map { try JSONEncoder().encode($0) })
        }

        init(_ record: LocalScanRecord) throws {
            confidence = record.confidenceScore
            biological = record.isBiological
            reasoning = record.aiReasoning
            tier = record.inferenceTier
            primary = try Self.json(record.primaryIdentificationData)
            provenance = try Self.json(record.identificationProvenanceData)
            candidates = try Self.json(record.candidatesData)
            pet = try Self.json(record.petIdentificationData)
        }

        init(_ display: AnalysisDisplaySnapshot) throws {
            confidence = display.confidenceScore
            biological = display.isBiological
            reasoning = display.aiReasoning
            tier = display.inferenceTier
            primary = try Self.json(display.primaryIdentificationData)
            provenance = try Self.json(display.identificationProvenanceData)
            candidates = try Self.json(display.candidatesData)
            pet = try Self.json(display.petIdentificationData)
        }

        private static func json(_ bytes: Data?) throws -> Data? {
            guard let bytes else { return nil }
            guard bytes.count <= maximumBytes else { throw Invalid.evidence }
            let value = try JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])
            return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        }
    }

    struct Proof: Codable, Equatable, Sendable {
        let version: Int
        let ownerID: UUID
        let scanID: UUID
        let generation: UUID
        let resultSHA256: String
        let projection: Projection
        let speciesID: String
        let pristineReviewSHA256: String
    }

    static func prepare(resultData: Data, mappedData: SpeciesData, scanID: String,
                        generation: UUID, account: InferenceCompletionAccountScope) throws -> Self {
        guard let id = UUID(uuidString: scanID), scanID == id.uuidString.lowercased(),
              mappedData.scanId?.lowercased() == scanID, mappedData.requiresSavedRecord,
              !resultData.isEmpty, resultData.count <= maximumBytes else { throw Invalid.evidence }
        let projection = try Projection(mappedData)
        _ = try encode(projection)
        return .init(scanID: scanID, generation: generation, account: account,
            resultSHA256: digest(resultData), projection: projection)
    }

    /// Caller has proved actual row absence and holds the scan locks. No await
    /// may separate this final check, insertion, and the owner's atomic save.
    func retain(on record: LocalScanRecord, context: ModelContext,
                backgroundOwnership: BackgroundAccountWorkOwnership? = nil) throws {
        guard record.id == scanID, try Self.pristine(record),
              try Self.encode(Projection(record)) == Self.encode(projection) else { throw Invalid.evidence }
        let id = OfflineQueueManager.scanIngestionJobId(scanId: scanID)
        guard let job = try context.fetchOfflineJob(id: id),
              job.kind == .scanIngestion, job.subjectId == scanID,
              job.status != .complete, job.status != .cancelled else { return }
        guard let metadata = job.metadataJSON else { return }
        var object = try Self.metadata(metadata)
        // Existing/damaged proof is never repaired, including after a replay.
        guard object[Self.metadataKey] == nil,
              InferenceGenerationMetadataContract.matches(generation, in: metadata),
              let funding = OfflineScanJobMetadataContract.funding(in: metadata),
              funding.accountId == account.ownerID, funding.scanId == scanID,
              funding.allowsDispatch,
              object["funding_reservation_released"] == nil else { return }
        if let backgroundOwnership {
            guard backgroundOwnership.ownerUserID == account.ownerID,
                  backgroundOwnership.generation == generation,
                  backgroundOwnership.phase == .inference,
                  OfflineScanJobMetadataContract.backgroundAccountWork(in: metadata) == backgroundOwnership else {
                throw Invalid.evidence
            }
        }
        let lower = scanID, upper = scanID.uppercased()
        let queued = try context.fetch(FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == lower || $0.id == upper }))
        guard queued.count == 1, let queue = queued.first, queue.id == scanID,
              queue.permitsOrdinaryInference,
              backgroundOwnership == nil || queue.queueState == .inferencing,
              try context.fetch(FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper })).isEmpty else {
            throw Invalid.evidence
        }
        let proof = Proof(version: 1, ownerID: account.ownerID, scanID: UUID(uuidString: scanID)!,
            generation: generation, resultSHA256: resultSHA256, projection: projection,
            speciesID: record.speciesId, pristineReviewSHA256: Self.pristineReviewDigest)
        object[Self.metadataKey] = try JSONSerialization.jsonObject(with: Self.encode(proof))
        guard let retained = OfflineScanJobMetadataContract.json(from: object),
              retained.utf8.count <= Self.maximumBytes else { throw Invalid.evidence }
        job.metadataJSON = retained
    }

    /// An existing proof-bearing row is immutable under original completion
    /// replay. In particular, never reconstruct its review defaults after Undo.
    static func preservesExisting(_ record: LocalScanRecord, incoming: Self?, context: ModelContext) throws -> Bool {
        guard let proof = try proof(for: record, context: context) else { return false }
        guard let incoming, proof.ownerID == incoming.account.ownerID,
              proof.scanID.uuidString.lowercased() == incoming.scanID,
              proof.generation == incoming.generation, proof.resultSHA256 == incoming.resultSHA256,
              try encode(proof.projection) == encode(incoming.projection) else { throw Invalid.evidence }
        return true
    }

    /// Absence is allowed for historical rows, but corruption is never absence.
    /// This does not inspect or acknowledge already-enrolled rows.
    static func retained(for record: LocalScanRecord, owner: UUID, context: ModelContext) throws -> Proof? {
        guard let proof = try proof(for: record, context: context) else { return nil }
        guard let job = try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: record.id)),
              job.status == .complete, proof.ownerID == owner, try pristine(record) else { throw Invalid.evidence }
        return proof
    }

    private static func proof(for record: LocalScanRecord, context: ModelContext) throws -> Proof? {
        guard let job = try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: record.id)),
              let raw = job.metadataJSON else { return nil }
        let object = try metadata(raw)
        guard let value = object[metadataKey] else { return nil }
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        let proof = try JSONDecoder().decode(Proof.self, from: bytes)
        guard try encode(proof) == bytes, proof.version == 1,
              proof.resultSHA256.count == 64, proof.resultSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              job.kind == .scanIngestion, job.subjectId == record.id,
              proof.scanID.uuidString.lowercased() == record.id,
              proof.speciesID == record.speciesId, try encode(proof.projection) == encode(Projection(record)),
              proof.pristineReviewSHA256 == pristineReviewDigest else { throw Invalid.evidence }
        return proof
    }

    private static func pristine(_ record: LocalScanRecord) throws -> Bool {
        let authority = try SharedMediaConsumerAuthority.classify(raw: record.mediaAuthorityRaw,
            consumerID: record.sharedMediaConsumerID, record: .scan)
        return authority == .legacy && record.analysisOwnerAccountID == nil && record.selectedAnalysisID == nil
            && record.observationStateRevision == nil && record.analysisSelectionInitialized
            && record.aiIdentificationReviewData == nil && record.confirmedSpeciesIdentityData == nil
            && record.confirmedSpeciesId == nil && record.userIdentificationOverride == nil
            && !record.userConfirmedIdentification && record.userReviewStateRaw == nil
    }

    // Versioned fingerprint of the exact absent review tuple, separate from the
    // original result. Defaults alone can never manufacture a retained Proof.
    private static let pristineReviewDigest = digest(Data("ordinary-review-v1:nil,nil,nil,nil,false,nil".utf8))

    private static func metadata(_ raw: String) throws -> [String: Any] {
        let bytes = Data(raw.utf8)
        guard bytes.count <= maximumBytes,
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) == bytes else { throw Invalid.evidence }
        return object
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(value)
        guard bytes.count <= maximumBytes else { throw Invalid.evidence }
        // Match the metadata serializer's spelling, including escaped slashes.
        return try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: bytes), options: [.sortedKeys])
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
