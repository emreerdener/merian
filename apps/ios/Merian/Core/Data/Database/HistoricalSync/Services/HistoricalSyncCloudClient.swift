import Foundation
import Supabase

/// Narrow Auth-lease and PostgREST adapter for historical library hydration.
///
/// `ScanRepository` owns synchronization policy and local side effects. This
/// adapter alone owns the live scan and collection projections so the
/// repository does not resolve the Supabase SDK directly.
@MainActor
struct HistoricalSyncCloudClient {
    private let beginAccountWorkHandler:
        @MainActor () throws -> AccountBoundWorkLease
    private let finishAccountWorkHandler:
        @MainActor (AccountBoundWorkLease) -> Void
    private let isAccountWorkCurrentHandler:
        @MainActor (AccountBoundWorkLease) -> Bool
    private let fetchScanPageHandler:
        @MainActor (HistoricalScanPageRequest) async throws -> Data
    private let fetchScanHandler:
        @MainActor (HistoricalScanRecordRequest) async throws -> Data
    private let fetchCollectionPageHandler:
        @MainActor (HistoricalCollectionPageRequest) async throws
            -> [CloudCollectionResponse]

    init(
        beginAccountWork:
            @escaping @MainActor () throws -> AccountBoundWorkLease,
        finishAccountWork:
            @escaping @MainActor (AccountBoundWorkLease) -> Void,
        isAccountWorkCurrent:
            @escaping @MainActor (AccountBoundWorkLease) -> Bool,
        fetchScanPage:
            @escaping @MainActor (HistoricalScanPageRequest) async throws
                -> Data,
        fetchScan:
            @escaping @MainActor (HistoricalScanRecordRequest) async throws
                -> Data,
        fetchCollectionPage:
            @escaping @MainActor (HistoricalCollectionPageRequest) async throws
                -> [CloudCollectionResponse]
    ) {
        beginAccountWorkHandler = beginAccountWork
        finishAccountWorkHandler = finishAccountWork
        isAccountWorkCurrentHandler = isAccountWorkCurrent
        fetchScanPageHandler = fetchScanPage
        fetchScanHandler = fetchScan
        fetchCollectionPageHandler = fetchCollectionPage
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

    func fetchScanPage(
        _ request: HistoricalScanPageRequest
    ) async throws -> Data {
        try await fetchScanPageHandler(request)
    }

    func fetchScan(
        _ request: HistoricalScanRecordRequest
    ) async throws -> Data {
        try await fetchScanHandler(request)
    }

    func fetchCollectionPage(
        _ request: HistoricalCollectionPageRequest
    ) async throws -> [CloudCollectionResponse] {
        try await fetchCollectionPageHandler(request)
    }

    static let live = HistoricalSyncCloudClient(
        beginAccountWork: {
            try SupabaseManager.shared.beginUnownedAccountBoundWork()
        },
        finishAccountWork: { lease in
            SupabaseManager.shared.finishAccountBoundWork(lease)
        },
        isAccountWorkCurrent: { lease in
            SupabaseManager.shared.isAccountBoundWorkLeaseCurrent(lease)
        },
        fetchScanPage: { request in
            try await SupabaseManager.shared.client
                .from("scans")
                .select(Self.historicalScanSelectColumns)
                .eq("user_id", value: request.userID)
                .order("timestamp", ascending: false)
                .range(
                    from: request.offset,
                    to: request.offset + request.pageSize - 1
                )
                .execute()
                .data
        },
        fetchScan: { request in
            try await SupabaseManager.shared.client
                .from("scans")
                .select(Self.historicalScanSelectColumns)
                .eq("user_id", value: request.userID)
                .eq("id", value: request.scanID)
                .limit(1)
                .execute()
                .data
        },
        fetchCollectionPage: { request in
            try await SupabaseManager.shared.client
                .from("collections")
                .select("id, name, created_at, collection_scans(scan_id)")
                .eq("user_id", value: request.userID)
                .range(
                    from: request.offset,
                    to: request.offset + request.pageSize - 1
                )
                .execute()
                .value
        }
    )

    private static let historicalScanSelectColumns =
        "id, image_storage_urls, video_storage_urls, audio_storage_urls, " +
        "captured_media, user_observation_context, timestamp, " +
        "weather_condition, weather_temperature_f, ai_confidence_score, " +
        "is_biological_subject, ecology_type, is_invasive, " +
        "invasive_status_region, invasive_rationale, invasive_confidence, " +
        "is_live_capture, colors, semantic_location, gps_lat_exact, " +
        "gps_long_exact, gps_elevation, ai_reasoning, estimated_size_cm, " +
        "life_stage, reproductive_condition, sex, sex_confidence, " +
        "sex_evidence, individual_count, ecological_interactions, " +
        "inference_tier, custom_tags, candidates, " +
        "user_identification_override, user_confirmed_identification, " +
        "image_quality_score, pet_identification, " +
        "explore_posts(id, unshared_at), " +
        "species_dictionary!scans_species_id_fkey(scientific_name, " +
        "kingdom, phylum, class, order, family, genus, wikipedia_url, " +
        "reference_image_url, hazard_type, common_names, " +
        "wikipedia_overview, iucn_red_list_status, habitat_description, " +
        "group_tags)"
}
