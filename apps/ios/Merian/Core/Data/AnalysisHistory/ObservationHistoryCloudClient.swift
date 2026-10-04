import Foundation
import Supabase

@MainActor
struct ObservationHistoryCloudClient {
    var begin: (UUID) throws -> AccountBoundWorkLease
    var isCurrent: (AccountBoundWorkLease) -> Bool
    var finish: (AccountBoundWorkLease) -> Void
    var fetch: (ObservationHistoryPageRequest) async throws -> Data
    var fetchState: (ObservationHistoryStateRequest) async throws -> Data = { _ in
        throw ObservationHistoryError.unavailable
    }

    // Explicit protocol-9 mutation. Server rollout gates remain closed.
    var select: (ObservationHistorySelectionRequest) async throws -> Data = { _ in
        throw ObservationHistoryError.unavailable
    }

    var enroll: (UUID) async throws -> Data = { _ in
        throw ObservationHistoryError.unavailable
    }

    static let live = Self(
        begin: { try SupabaseManager.shared.beginUnownedAccountBoundWork(expectedUserID: $0) },
        isCurrent: { SupabaseManager.shared.isAccountBoundWorkLeaseCurrent($0) },
        finish: { SupabaseManager.shared.finishAccountBoundWork($0) },
        fetch: { request in
            struct Parameters: Encodable {
                let p_request: ObservationHistoryPageRequest
                let p_reader = 9
            }
            return try await SupabaseManager.shared.client
                .rpc("get_owned_observation_analysis_page", params: Parameters(p_request: request))
                .execute().data
        },
        fetchState: { request in
            struct Parameters: Encodable {
                let p_request: ObservationHistoryStateRequest
                let p_reader = 9
            }
            return try await SupabaseManager.shared.client
                .rpc("get_owned_observation_analysis_state", params: Parameters(p_request: request))
                .execute().data
        },
        select: { request in
            struct Parameters: Encodable {
                let p_request: ObservationHistorySelectionRequest
                let p_reader = 9
            }
            return try await SupabaseManager.shared.client
                .rpc("select_owned_observation_analysis", params: Parameters(p_request: request))
                .execute().data
        },
        enroll: { observationID in
            struct Parameters: Encodable {
                let p_observation: String
                let p_reader = 9
            }
            return try await SupabaseManager.shared.client
                .rpc("enroll_owned_observation_history", params: Parameters(p_observation: observationID.uuidString.lowercased()))
                .execute().data
        }
    )
}
