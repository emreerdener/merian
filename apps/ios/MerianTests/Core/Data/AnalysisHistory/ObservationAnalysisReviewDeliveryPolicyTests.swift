import Foundation
@testable import Merian
import Testing

@MainActor
struct ObservationAnalysisReviewDeliveryPolicyTests {
    @Test func permanentFailuresAreExactAndBounded() {
        let permanent: [(Int, String, String?)] = [
            (400, "invalid_analysis_history", nil), (404, "analysis_history_not_found", nil),
            (409, "analysis_history_operation_conflict", nil), (409, "species_review_requires_primary", nil),
            (422, "species_not_verified", nil), (400, "P0002", "analysis_history_not_found"),
            (400, "22023", "invalid_identification_review"), (400, "22023", "analysis_history_operation_conflict")
        ]
        for (status, code, message) in permanent {
            let bytes = try! JSONSerialization.data(withJSONObject: ["code": code, "message": message ?? "Synthetic explanation"])
            #expect(ObservationAnalysisReviewDeliveryPolicy.requiresAttention(MerianError.httpError(statusCode: status, message: String(decoding: bytes, as: UTF8.self))))
        }
        for error: Error in [URLError(.timedOut), CocoaError(.fileWriteUnknown),
            MerianError.httpError(statusCode: 404, message: "{\"code\":\"NOT_FOUND\"}"),
            MerianError.httpError(statusCode: 500, message: "{\"code\":\"invalid_analysis_history\"}"),
            MerianError.httpError(statusCode: 400, message: "{\"code\":\"P0002\",\"message\":\"unrelated_missing_row\"}"),
            MerianError.httpError(statusCode: 400, message: "{\"code\":\"55000\",\"message\":\"analysis_history_unavailable\"}"),
            MerianError.httpError(statusCode: 429, message: "{\"code\":\"analysis_history_not_found\"}"),
            MerianError.httpError(statusCode: 400, message: String(repeating: " ", count: 8193)),
            ObservationHistoryStateSyncService.AdmissionError.staleRevision,
            ObservationHistoryStateSyncService.AdmissionError.conflictingRevision,
            ObservationHistoryStateSyncService.AdmissionError.pendingReview,
            LocalAnalysisStateRecord.StorageError.staleRevision] {
            #expect(!ObservationAnalysisReviewDeliveryPolicy.requiresAttention(error))
        }
    }

    @Test func invalidImmutableStateAndMissingDisplayHoldRatherThanRebase() {
        for error: Error in [MerianError.invalidResponse, ObservationHistoryError.invalidSnapshot, ObservationHistoryError.resultConflict,
            ObservationHistoryStateSyncService.AdmissionError.selectionProjectionRequired,
            ObservationHistoryStateSyncService.AdmissionError.authorityStorageRequired,
            LocalAnalysisStateRecord.StorageError.conflictingDisplay, LocalAnalysisStateRecord.StorageError.conflictingRevision] {
            #expect(ObservationAnalysisReviewDeliveryPolicy.requiresAttention(error))
        }
    }
}
