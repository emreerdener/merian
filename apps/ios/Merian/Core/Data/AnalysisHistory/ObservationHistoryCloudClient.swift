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

    // Explicit protocol-11 mutation. Server rollout gates remain closed.
    var select: (ObservationHistorySelectionRequest) async throws -> Data = { _ in
        throw ObservationHistoryError.unavailable
    }

    var enroll: (UUID) async throws -> Data = { _ in
        throw ObservationHistoryError.unavailable
    }

    var recoverBaseline: (UUID) async throws -> Data = { _ in
        throw ObservationHistoryError.unavailable
    }

    var reconcileEnrollment: (UUID) async throws -> Data = { _ in
        throw ObservationHistoryEnrollmentService.AdmissionError.reconciliationRequired
    }

    var resolvePhoto: (ObservationHistoryPhotoRequest) async throws -> ObservationHistoryPhotoTicket = { _ in
        throw ObservationHistoryError.unavailable
    }

    static let live = Self.live(manager: .shared)

    static func live(manager: SupabaseManager) -> Self {
        Self(
            begin: { try manager.beginUnownedAccountBoundWork(expectedUserID: $0) },
            isCurrent: { manager.isAccountBoundWorkLeaseCurrent($0) },
            finish: { manager.finishAccountBoundWork($0) },
            fetch: { request in
                struct Parameters: Encodable {
                    let p_request: ObservationHistoryPageRequest
                    let p_reader = 13
                }
                return try await manager.client
                    .rpc("get_owned_observation_analysis_page", params: Parameters(p_request: request))
                    .execute().data
            },
            fetchState: { request in
                struct Parameters: Encodable {
                    let p_request: ObservationHistoryStateRequest
                    let p_reader = 13
                }
                return try await manager.client
                    .rpc("get_owned_observation_analysis_state", params: Parameters(p_request: request))
                    .execute().data
            },
            select: { request in
                struct Parameters: Encodable {
                    let p_request: ObservationHistorySelectionRequest
                    let p_reader = 11
                }
                return try await manager.client
                    .rpc("select_owned_observation_analysis", params: Parameters(p_request: request))
                    .execute().data
            },
            enroll: { observationID in
                struct Parameters: Encodable {
                    let p_observation: String
                    let p_reader = 9
                }
                return try await manager.client
                    .rpc("enroll_owned_observation_history", params: Parameters(p_observation: observationID.uuidString.lowercased()))
                    .execute().data
            },
            recoverBaseline: { observationID in
                struct Request: Encodable {
                    let schema_version = 1
                    let observation_id: String
                }
                struct Parameters: Encodable {
                    let p_request: Request
                    let p_reader = 9
                }
                return try await manager.client.rpc("get_owned_observation_enrollment_baseline",
                    params: Parameters(p_request: Request(observation_id: observationID.uuidString.lowercased())))
                    .execute().data
            },
            reconcileEnrollment: { observationID in
                struct Request: Encodable {
                    let schema_version = 1
                    let observation_id: String
                }
                struct Parameters: Encodable {
                    let p_request: Request
                    let p_reader = 11
                }
                return try await manager.client.rpc("get_owned_observation_enrollment_selection",
                    params: Parameters(p_request: Request(observation_id: observationID.uuidString.lowercased())))
                    .execute().data
            },
            resolvePhoto: { request in
                try await manager.client.functions.invoke("resolve-history-photo", options: .init(body: request))
            }
        )
    }
}
