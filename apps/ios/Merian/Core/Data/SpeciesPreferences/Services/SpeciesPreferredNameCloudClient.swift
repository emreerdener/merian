import Foundation
import Supabase

/// Narrow PostgREST and Auth-lease adapter for species-preference sync.
///
/// The sync coordinator receives this value through its initializer. Direct
/// `SupabaseManager.shared` resolution remains confined to the live adapter so
/// synchronization policy and state can be tested without a live session.
@MainActor
struct SpeciesPreferredNameCloudClient {
    private let beginAccountWorkHandler:
        @MainActor () throws -> AccountBoundWorkLease
    private let finishAccountWorkHandler:
        @MainActor (AccountBoundWorkLease) -> Void
    private let isAccountWorkCurrentHandler:
        @MainActor (AccountBoundWorkLease) -> Bool
    private let fetchPageHandler:
        @MainActor (SpeciesPreferenceCloudPageRequest) async throws
            -> [SpeciesPreferenceCloudRow]
    private let upsertHandler:
        @MainActor ([SpeciesPreferenceCloudUpsert]) async throws -> Void

    init(
        beginAccountWork:
            @escaping @MainActor () throws -> AccountBoundWorkLease,
        finishAccountWork:
            @escaping @MainActor (AccountBoundWorkLease) -> Void,
        isAccountWorkCurrent:
            @escaping @MainActor (AccountBoundWorkLease) -> Bool,
        fetchPage:
            @escaping @MainActor (SpeciesPreferenceCloudPageRequest) async throws
                -> [SpeciesPreferenceCloudRow],
        upsert:
            @escaping @MainActor ([SpeciesPreferenceCloudUpsert]) async throws
                -> Void
    ) {
        beginAccountWorkHandler = beginAccountWork
        finishAccountWorkHandler = finishAccountWork
        isAccountWorkCurrentHandler = isAccountWorkCurrent
        fetchPageHandler = fetchPage
        upsertHandler = upsert
    }

    func beginAccountWork() throws -> AccountBoundWorkLease {
        try beginAccountWorkHandler()
    }

    func finishAccountWork(_ lease: AccountBoundWorkLease) {
        finishAccountWorkHandler(lease)
    }

    func isAccountWorkCurrent(_ lease: AccountBoundWorkLease) -> Bool {
        isAccountWorkCurrentHandler(lease)
    }

    func fetchPage(
        _ request: SpeciesPreferenceCloudPageRequest
    ) async throws -> [SpeciesPreferenceCloudRow] {
        try await fetchPageHandler(request)
    }

    func upsert(_ values: [SpeciesPreferenceCloudUpsert]) async throws {
        try await upsertHandler(values)
    }

    static let live = SpeciesPreferredNameCloudClient(
        beginAccountWork: {
            try SupabaseManager.shared.beginUnownedAccountBoundWork()
        },
        finishAccountWork: { lease in
            SupabaseManager.shared.finishAccountBoundWork(lease)
        },
        isAccountWorkCurrent: { lease in
            SupabaseManager.shared.isAccountBoundWorkLeaseCurrent(lease)
        },
        fetchPage: { request in
            var query = SupabaseManager.shared.client
                .from("user_species_preferences")
                .select(
                    "scientific_name, preferred_common_name, updated_at, deleted_at"
                )
                .eq("user_id", value: request.userID)
            if let cursor = request.afterScientificName {
                query = query.gt("scientific_name", value: cursor)
            }
            return try await query
                .order("scientific_name", ascending: true)
                .limit(request.pageSize)
                .execute()
                .value
        },
        upsert: { values in
            try await SupabaseManager.shared.client
                .from("user_species_preferences")
                .upsert(values, onConflict: "user_id,scientific_name")
                .execute()
        }
    )
}
