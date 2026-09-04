import Foundation
import Testing

@testable import Merian

@Suite("Inference Request Policy")
struct InferenceRequestPolicyTests {
    @Test func authenticatedInferenceRequestRemainsBoundToOriginalAuthSession() throws {
        let sourceUserID = UUID()
        let url = try #require(URL(string: "https://example.com/identify"))
        let request = AuthenticatedInferenceRequest(
            request: URLRequest(url: url),
            expectedAuthUserID: sourceUserID
        )

        #expect(
            request.isBound(
                to: AuthTransitionSession(
                    userID: sourceUserID,
                    isAnonymous: false
                )
            )
        )
        #expect(
            !request.isBound(
                to: AuthTransitionSession(
                    userID: UUID(),
                    isAnonymous: true
                )
            )
        )
    }

    @Test func inferenceObjectKeysMustBelongToExactRequestAccount() {
        let sourceUserID = UUID()
        let otherUserID = UUID()
        let sourceKey = MediaStagingContract.objectKey(
            userId: sourceUserID.uuidString,
            fileName: "scan_image.webp"
        )
        let otherKey = MediaStagingContract.objectKey(
            userId: otherUserID.uuidString,
            fileName: "scan_audio.wav"
        )

        #expect(
            MerianNetworkClient.inferenceObjectKeysBelongToExpectedUser(
                [[sourceKey], []],
                expectedAuthUserID: sourceUserID
            )
        )
        #expect(
            !MerianNetworkClient.inferenceObjectKeysBelongToExpectedUser(
                [[sourceKey], [otherKey]],
                expectedAuthUserID: sourceUserID
            )
        )
        #expect(
            !MerianNetworkClient.inferenceObjectKeysBelongToExpectedUser(
                [["staging/not-a-uuid/scan.webp"]],
                expectedAuthUserID: sourceUserID
            )
        )
    }

    @Test func testRecoverableInferenceConflictRequiresKnown409Code() {
        let recoverableCodes = [
            "ai_request_already_completed",
            "ai_request_in_progress",
            "scan_already_complete",
            "scan_already_finalized"
        ]

        for code in recoverableCodes {
            let error = MerianError.httpError(
                statusCode: 409,
                message: #"{"error":"Observation recovery in progress.","code":"\#(code)"}"#
            )
            #expect(MerianNetworkClient.isRecoverableInferenceConflict(error))
        }

        #expect(!MerianNetworkClient.isRecoverableInferenceConflict(
            MerianError.httpError(
                statusCode: 409,
                message: #"{"error":"Conflict.","code":"different_conflict"}"#
            )
        ))
        #expect(!MerianNetworkClient.isRecoverableInferenceConflict(
            MerianError.httpError(
                statusCode: 503,
                message: #"{"error":"Retry.","code":"ai_request_in_progress"}"#
            )
        ))
        #expect(!MerianNetworkClient.isRecoverableInferenceConflict(
            MerianError.httpError(
                statusCode: 409,
                message: #"{"error":"Conflict.","code":"INVALID CODE"}"#
            )
        ))
    }
}
