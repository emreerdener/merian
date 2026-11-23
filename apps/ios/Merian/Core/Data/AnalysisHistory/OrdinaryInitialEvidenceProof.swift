import Foundation

/// A server completion assertion bound to the exact locally frozen submission.
/// This is separate from the older local display fingerprint, and never grants
/// enrollment or media access by itself.
struct OrdinaryInitialEvidenceProof: Codable, Equatable, Sendable {
    let ownerID: UUID
    let scanID: UUID
    let generation: UUID
    let evidenceDigest: String

    static let expectationKey = "initial_evidence_expectation_v1"
    static let completionKey = "initial_evidence_completion_v1"
    static let resultKey = "initial_evidence_result_sha256_v1"

    /// Server DSP determines the evidence digest after dispatch. The app freezes
    /// this identity, not a guessed digest of server-prepared audio.
    var submission: OrdinaryInitialSubmissionIdentity {
        .init(ownerID: ownerID, scanID: scanID, generation: generation)
    }

    init(_ value: InitialEvidenceCompletionDTO) throws {
        ownerID = try ObservationHistoryPage.uuid(value.ownerID)
        scanID = try ObservationHistoryPage.uuid(value.scanID)
        generation = try ObservationHistoryPage.uuid(value.generation)
        evidenceDigest = value.evidenceDigest
        try validate()
    }
    func validate() throws {
        guard Set([ownerID, scanID, generation]).count == 3,
              evidenceDigest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw OrdinaryInferenceCompletion.Invalid.evidence
        }
    }
    func matches(_ result: ObservationHistoryPage.Result) -> Bool {
        guard result.version == 8, let evidence = result.initialEvidence else { return false }
        guard let object = try? JSONSerialization.jsonObject(with: result.bytes) as? [String: Any],
              object["observation_id"] as? String == scanID.uuidString.lowercased() else { return false }
        return evidence.ownerID == ownerID && evidence.generation == generation && evidence.digest == evidenceDigest
    }
    func object() throws -> Any {
        try validate()
        return try JSONSerialization.jsonObject(with: JSONEncoder().encode(self))
    }
    static func read(_ value: Any?) throws -> Self? {
        guard let value else { return nil }
        let object = try ObservationHistoryPage.object(value, keys: ["ownerID", "scanID", "generation", "evidenceDigest"])
        let proof = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: object))
        try proof.validate()
        return proof
    }
}

struct OrdinaryInitialSubmissionIdentity: Codable, Equatable, Sendable {
    let ownerID: UUID
    let scanID: UUID
    let generation: UUID

    func object() throws -> Any {
        guard Set([ownerID, scanID, generation]).count == 3 else { throw OrdinaryInferenceCompletion.Invalid.evidence }
        return try JSONSerialization.jsonObject(with: JSONEncoder().encode(self))
    }

    static func read(_ value: Any?) throws -> Self? {
        guard let value else { return nil }
        let object = try ObservationHistoryPage.object(value, keys: ["ownerID", "scanID", "generation"])
        let identity = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: object))
        _ = try identity.object()
        return identity
    }
}
