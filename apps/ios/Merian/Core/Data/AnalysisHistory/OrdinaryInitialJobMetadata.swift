import Foundation

/// Canonical initial job metadata. This binds an already claimed reservation to
/// the frozen submission; constructing it does not claim funding or admit work.
struct OrdinaryInitialJobMetadata: Equatable, Sendable {
    let identity: OrdinaryInitialSubmissionIdentity
    let funding: ScanFundingReservation
    let json: String

    init(identity: OrdinaryInitialSubmissionIdentity, funding: ScanFundingReservation) throws {
        _ = try identity.object()
        guard funding.accountId == identity.ownerID,
              funding.scanId == identity.scanID.uuidString.lowercased(),
              funding.createdAt.timeIntervalSince1970.isFinite,
              Set(funding.blockerScanIds).count == funding.blockerScanIds.count,
              funding.blockerScanIds.allSatisfy({ value in
                  UUID(uuidString: value)?.uuidString.lowercased() == value && value != funding.scanId
              }),
              let base = OfflineScanJobMetadataContract.json(generation: identity.generation, funding: funding),
              OfflineScanJobMetadataContract.unreleasedFundingForObservation(in: base) == funding,
              InferenceGenerationMetadataContract.matches(identity.generation, in: base) else {
            throw OrdinaryInferenceCompletion.Invalid.evidence
        }
        var object = OfflineScanJobMetadataContract.object(from: base)
        object[OrdinaryInitialEvidenceProof.expectationKey] = try identity.object()
        guard let json = OfflineScanJobMetadataContract.json(from: object) else {
            throw OrdinaryInferenceCompletion.Invalid.evidence
        }
        self.identity = identity; self.funding = funding; self.json = json
    }

    /// Acceptance readback requires the exact initial metadata, not a lossy
    /// decoder that ignores an injected release/completion/background sidecar.
    func requireInitialReadback(_ actual: String?) throws {
        guard actual == json,
              OfflineScanJobMetadataContract.unreleasedFundingForObservation(in: actual) == funding,
              InferenceGenerationMetadataContract.matches(identity.generation, in: actual),
              try OrdinaryInitialSubmissionIdentity.read(
                  OfflineScanJobMetadataContract.object(from: actual)[OrdinaryInitialEvidenceProof.expectationKey]
              ) == identity else { throw OrdinaryInferenceCompletion.Invalid.evidence }
    }
}
