import Foundation

/// A saved dispatch intent is a one-way local boundary. Its presence authorizes
/// recovery only, never reconstruction of permission to call Identify again.
@MainActor
enum SharedMediaCaptureExecutionIntent {
    struct Dispatch: Codable, Equatable, Sendable {
        let version: Int
        let id: UUID
        let scanID: UUID
        let generation: UUID
        let attemptCount: Int
        var fundingResolutionSHA256: String?
    }
    static let key = "capture_dispatch_intent_v1"

    static func read(_ raw: String?, submission: SharedMediaCaptureSubmission) throws -> Dispatch? {
        guard let raw, raw.utf8.count <= OrdinaryInferenceCompletion.maximumBytes else { throw SharedMediaStorageFailure.conflict }
        var fields = OfflineScanJobMetadataContract.object(from: raw)
        let value = fields.removeValue(forKey: key)
        let resolution = try SharedMediaCaptureFundingResolution.read(raw, submission: submission)
        fields.removeValue(forKey: SharedMediaCaptureFundingResolution.key)
        guard OfflineScanJobMetadataContract.json(from: fields)
                == (try SharedMediaCaptureFundingResolution.baseMetadata(raw, submission: submission)) else {
            throw SharedMediaStorageFailure.conflict
        }
        guard let value else { return nil }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        let dispatch = try JSONDecoder().decode(Dispatch.self, from: data)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(dispatch) == data, dispatch.version == 1,
              dispatch.scanID == submission.scanID, dispatch.generation == submission.generation,
              dispatch.fundingResolutionSHA256 == (try resolution?.digest),
              dispatch.attemptCount > 0,
              dispatch.attemptCount <= OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts else {
            throw SharedMediaStorageFailure.conflict
        }
        return dispatch
    }

    static func reserving(submission: SharedMediaCaptureSubmission, attemptCount: Int,
                          metadata: String? = nil) throws -> String {
        let metadata = metadata ?? submission.context.jobMetadataJSON
        guard try read(metadata, submission: submission) == nil else { throw SharedMediaStorageFailure.conflict }
        let dispatch = Dispatch(version: 1, id: UUID(), scanID: submission.scanID,
            generation: submission.generation, attemptCount: attemptCount,
            fundingResolutionSHA256: try SharedMediaCaptureFundingResolution.read(metadata, submission: submission)?.digest)
        var fields = OfflineScanJobMetadataContract.object(from: metadata)
        fields[key] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(dispatch))
        guard let raw = OfflineScanJobMetadataContract.json(from: fields),
              try read(raw, submission: submission) == dispatch else { throw SharedMediaStorageFailure.conflict }
        return raw
    }
}
