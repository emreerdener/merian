import Foundation

/// Only exact permanent contract failures hold work. Network and revision races retain bounded retry.
enum ObservationAnalysisReviewDeliveryPolicy {
    static func requiresAttention(_ error: Error) -> Bool {
        if let error = error as? ObservationHistoryError {
            return [.invalidPage, .invalidSnapshot, .resultConflict].contains(error)
        }
        if let error = error as? ObservationHistoryStateSyncService.AdmissionError {
            return error == .selectionProjectionRequired || error == .authorityStorageRequired
        }
        if let error = error as? LocalAnalysisStateRecord.StorageError {
            return error != .staleRevision
        }
        guard let error = error as? MerianError else { return false }
        if case .invalidResponse = error { return true }
        guard case let .httpError(status, message) = error, (400..<500).contains(status), message.utf8.count <= 8192,
              let row = try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any],
              let code = row["code"] as? String else { return false }
        if permanentRPC(code: code, message: row["message"] as? String) { return true }
        switch (status, code) {
        case (400, "invalid_analysis_history"), (404, "analysis_history_not_found"), (404, "analysis_history_deleted"),
             (409, "analysis_history_operation_conflict"), (409, "analysis_history_revision_conflict"),
             (409, "species_review_requires_primary"), (422, "species_not_verified"): return true
        default: return false
        }
    }

    static func permanentRPC(code: String?, message: String?) -> Bool {
        switch (code, message) {
        case ("P0002", "analysis_history_not_found"), ("22023", "invalid_analysis_history"),
             ("22023", "invalid_identification_review"), ("22023", "analysis_history_operation_conflict"): return true
        default: return false
        }
    }
}
