import Foundation

/// A write-once local admission decision, separate from the immutable submitted
/// context and from the server's eventual quota/credit settlement. The owning
/// resolver must qualify the evidence and commit it with operational funding.
struct SharedMediaCaptureFundingResolution: Codable, Equatable, Sendable {
    static let key = "capture_funding_resolution_v1"
    let version: Int
    let ownerID: UUID
    let scanID: UUID
    let generation: UUID
    let originalContextSHA256: String
    let evidenceSHA256: String
    let effective: ScanFundingReservation

    @MainActor
    init(submission: SharedMediaCaptureSubmission, effective: ScanFundingReservation,
         evidenceSHA256: String) throws {
        version = 1; ownerID = submission.profile.ownerID
        scanID = submission.scanID; generation = submission.generation
        originalContextSHA256 = try Self.contextDigest(submission)
        self.evidenceSHA256 = evidenceSHA256; self.effective = effective
        try validate(submission)
    }

    @MainActor
    func validate(_ submission: SharedMediaCaptureSubmission) throws {
        let original = try submission.context.metadata(plan: submission.plan()).funding
        guard version == 1, ownerID == submission.profile.ownerID, scanID == submission.scanID,
              generation == submission.generation, originalContextSHA256 == (try Self.contextDigest(submission)),
              SharedMediaAcquisitionEncoding.isHash(evidenceSHA256), original.source == .deferredFlash,
              effective.accountId == original.accountId, effective.scanId == original.scanId,
              effective.createdAt == original.createdAt, effective.allowsDispatch,
              effective.blockerScanIds.isEmpty else { throw SharedMediaStorageFailure.conflict }
    }

    var digest: String {
        get throws { try SharedMediaAcquisitionEncoding.digest(SharedMediaAcquisitionEncoding.encode(self, maximum: 8192)) }
    }

    @MainActor
    static func read(_ raw: String, submission: SharedMediaCaptureSubmission) throws -> Self? {
        let object = OfflineScanJobMetadataContract.object(from: raw)
        guard let value = object[key] else { return nil }
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        let result: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: 8192)
        guard try SharedMediaAcquisitionEncoding.encode(result, maximum: 8192) == bytes else {
            throw SharedMediaStorageFailure.conflict
        }
        try result.validate(submission)
        return result
    }

    /// Expected operational base. Nothing changes the original context. A
    /// different live funding field without this exact receipt is invalid.
    @MainActor
    static func baseMetadata(_ raw: String, submission: SharedMediaCaptureSubmission) throws -> String {
        guard let resolution = try read(raw, submission: submission) else { return submission.context.jobMetadataJSON }
        guard let result = OfflineScanJobMetadataContract.settingFunding(resolution.effective, in: submission.context.jobMetadataJSON) else {
            throw SharedMediaStorageFailure.conflict
        }
        return result
    }

    @MainActor
    static func funding(_ raw: String, submission: SharedMediaCaptureSubmission) throws -> ScanFundingReservation {
        let original = try submission.context.metadata(plan: submission.plan()).funding
        let expected = try read(raw, submission: submission)?.effective ?? original
        guard OfflineScanJobMetadataContract.unreleasedFundingForObservation(in: raw) == expected else {
            throw SharedMediaStorageFailure.conflict
        }
        return expected
    }

    /// Terminal metadata may add only the existing completion and settlement
    /// records. The dispatch still binds the same resolution after release.
    @MainActor
    static func requireOperationalCustody(_ raw: String, submission: SharedMediaCaptureSubmission) throws {
        let resolution = try read(raw, submission: submission)
        var operational = OfflineScanJobMetadataContract.object(from: raw)
        let settlement = operational.removeValue(forKey: SharedMediaCaptureFundingReceipt.key)
        for key in [OrdinaryInferenceCompletion.metadataKey,
                    OrdinaryInitialEvidenceProof.completionKey, OrdinaryInitialEvidenceProof.resultKey] {
            operational.removeValue(forKey: key)
        }
        guard let text = OfflineScanJobMetadataContract.json(from: operational) else { throw SharedMediaStorageFailure.conflict }
        let dispatch = try SharedMediaCaptureExecutionIntent.read(text, submission: submission)
        if settlement != nil {
            guard resolution == nil || dispatch != nil else { throw SharedMediaStorageFailure.conflict }
            guard try SharedMediaCaptureFundingReceipt.read(raw).resolutionSHA256 == resolution?.digest else {
                throw SharedMediaStorageFailure.conflict
            }
        }
    }

    @MainActor
    func retaining(in raw: String, submission: SharedMediaCaptureSubmission) throws -> String {
        try validate(submission)
        guard try SharedMediaCaptureExecutionIntent.read(raw, submission: submission) == nil else {
            throw SharedMediaStorageFailure.closed
        }
        if let saved = try Self.read(raw, submission: submission) {
            guard saved == self else { throw SharedMediaStorageFailure.conflict }
            return raw
        }
        guard raw == submission.context.jobMetadataJSON else { throw SharedMediaStorageFailure.conflict }
        var fields = OfflineScanJobMetadataContract.object(from:
            OfflineScanJobMetadataContract.settingFunding(effective, in: raw))
        fields[Self.key] = try JSONSerialization.jsonObject(with: SharedMediaAcquisitionEncoding.encode(self, maximum: 8192))
        guard let result = OfflineScanJobMetadataContract.json(from: fields),
              result.utf8.count <= OrdinaryInferenceCompletion.maximumBytes,
              try Self.read(result, submission: submission) == self,
              try Self.funding(result, submission: submission) == effective else { throw SharedMediaStorageFailure.conflict }
        return result
    }

    @MainActor
    private static func contextDigest(_ submission: SharedMediaCaptureSubmission) throws -> String {
        try SharedMediaAcquisitionEncoding.digest(SharedMediaAcquisitionEncoding.encode(
            submission.context, maximum: Int(PhotoPreparationPolicy.metadata)))
    }
}
