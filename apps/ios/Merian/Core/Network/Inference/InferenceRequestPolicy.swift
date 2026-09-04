import Foundation

enum InferenceRequestPolicy {
    static func objectKeysBelongToExpectedUser(
        _ objectKeyGroups: [[String]],
        expectedAuthUserID: UUID
    ) -> Bool {
        let expectedOwner = expectedAuthUserID.uuidString.lowercased()
        return objectKeyGroups.joined().allSatisfy {
            MediaStagingContract.ownerId(fromObjectKey: $0) == expectedOwner
        }
    }

    static func isRecoverableConflict(statusCode: Int, stableCode: String?) -> Bool {
        guard statusCode == 409, let stableCode else { return false }
        return stableCode == "ai_request_already_completed"
            || stableCode == "ai_request_in_progress"
            || stableCode == "scan_already_complete"
            || stableCode == "scan_already_finalized"
    }
}

extension MerianNetworkClient {
    static func inferenceObjectKeysBelongToExpectedUser(
        _ objectKeyGroups: [[String]],
        expectedAuthUserID: UUID
    ) -> Bool {
        InferenceRequestPolicy.objectKeysBelongToExpectedUser(
            objectKeyGroups,
            expectedAuthUserID: expectedAuthUserID
        )
    }

    static func isRecoverableInferenceConflict(_ error: Error) -> Bool {
        guard case let MerianError.httpError(statusCode, _) = error else {
            return false
        }
        return InferenceRequestPolicy.isRecoverableConflict(
            statusCode: statusCode,
            stableCode: EdgeFunctionErrorPolicy.stableCode(from: error)
        )
    }
}
