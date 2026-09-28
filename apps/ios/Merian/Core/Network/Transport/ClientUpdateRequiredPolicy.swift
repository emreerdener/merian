import Foundation
import Supabase

enum ClientUpdateRequiredPolicy {
    static func matches(_ error: Error) -> Bool {
        if let error = error as? PostgrestError {
            return error.code == "PT426" && error.message == "client_update_required"
        }
        guard case MerianError.httpError(let status, _) = error else { return false }
        return status == 426 && EdgeFunctionErrorPolicy.stableCode(from: error) == "client_update_required"
    }
}
