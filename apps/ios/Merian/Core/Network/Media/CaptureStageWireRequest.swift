import Foundation

/// One exact client artifact. This value is not an upload or original-release permit.
struct CaptureStageWireRequest: Sendable {
    static let maximumMetadataBytes = 1_044_736
    let plan: CaptureInitialEvidencePlan
    let mediaID: UUID
    let body: Data

    init(plan: CaptureInitialEvidencePlan, mediaID: UUID, bytes: Data) throws {
        guard let artifact = plan.uploads.first(where: { $0.artifact.mediaID == mediaID })?.artifact,
              bytes.count == artifact.byteCount,
              SharedMediaAcquisitionEncoding.digest(bytes) == artifact.sha256 else { throw MerianError.invalidResponse }
        let metadata = try JSONSerialization.data(withJSONObject: [
            "schema_version": 1, "plan": plan.object, "media_id": mediaID.uuidString.lowercased()
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        guard metadata.count <= Self.maximumMetadataBytes else { throw MerianError.payloadTooLarge }
        let length = UInt32(metadata.count)
        var body = Data([UInt8(length >> 24), UInt8((length >> 16) & 255), UInt8((length >> 8) & 255), UInt8(length & 255)])
        body.append(metadata); body.append(bytes)
        self.plan = plan; self.mediaID = mediaID; self.body = body
    }
}

/// Readiness of one artifact only. It does not prove a retained History seal,
/// provider completion, or permission to release any original.
struct CaptureStageReceipt: Equatable, Sendable {
    static let maximumBytes = 1024
    let ownerID: UUID
    let scanID: UUID
    let generation: UUID
    let mediaID: UUID
    let planSHA256: String
    let requestSHA256: String

    init(data: Data, wire: CaptureStageWireRequest, previous: Self? = nil) throws {
        guard data.count <= Self.maximumBytes else { throw MerianError.invalidResponse }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data),
            keys: ["schema_version", "scan_id", "generation", "request_sha256", "media_id", "ready"])
        guard try ObservationHistoryPage.integer(row["schema_version"]) == 1,
              row["scan_id"] as? String == wire.plan.scanID.uuidString.lowercased(),
              row["generation"] as? String == wire.plan.generation.uuidString.lowercased(),
              row["media_id"] as? String == wire.mediaID.uuidString.lowercased(),
              let ready = row["ready"] as? NSNumber, CFGetTypeID(ready) == CFBooleanGetTypeID(), ready.boolValue,
              let digest = row["request_sha256"] as? String, SharedMediaAcquisitionEncoding.isHash(digest) else {
            throw MerianError.invalidResponse
        }
        ownerID = wire.plan.ownerID; scanID = wire.plan.scanID; generation = wire.plan.generation
        mediaID = wire.mediaID; planSHA256 = try SharedMediaAcquisitionEncoding.digest(wire.plan.encoded())
        requestSHA256 = digest
        if let previous {
            // An earlier artifact may bind this cohort; it cannot bind another plan.
            guard previous.ownerID == ownerID, previous.scanID == scanID, previous.generation == generation,
                  previous.planSHA256 == planSHA256, previous.requestSHA256 == requestSHA256 else { throw MerianError.invalidResponse }
        }
    }

    func requirePlan(_ plan: CaptureInitialEvidencePlan) throws {
        guard ownerID == plan.ownerID, scanID == plan.scanID, generation == plan.generation,
              planSHA256 == (try SharedMediaAcquisitionEncoding.digest(plan.encoded())),
              plan.uploads.contains(where: { $0.artifact.mediaID == mediaID }) else { throw MerianError.invalidResponse }
    }

    /// Restores only a locally verified acknowledgement, preserving the exact
    /// server checksum independently of the native plan and physical-file hash.
    init(saved: SharedMediaCaptureRemoteStage, plan: CaptureInitialEvidencePlan,
         request: SharedMediaCaptureArtifactRequest, stage: SharedMediaCaptureArtifactStage) throws {
        try saved.validate(request: request, stage: stage)
        let input = try plan.artifactInput(mediaID: request.mediaID, id: request.id)
        guard request.profile.ownerID == plan.ownerID, request.scanID == plan.scanID,
              request.submissionGeneration == plan.generation,
              input.matches(request) || input.bindsSource(request),
              let upload = plan.uploads.first(where: { $0.artifact.mediaID == request.mediaID }),
              upload.role.rawValue == request.role.rawValue,
              upload.frameIndex == request.frameIndex, upload.artifact.byteCount == request.byteCount,
              upload.artifact.sha256 == request.sha256, upload.artifact.contentType == request.contentType else {
            throw MerianError.invalidResponse
        }
        ownerID = plan.ownerID; scanID = plan.scanID; generation = plan.generation
        mediaID = request.mediaID; planSHA256 = input.planSHA256; requestSHA256 = saved.serverRequestSHA256
    }
}
