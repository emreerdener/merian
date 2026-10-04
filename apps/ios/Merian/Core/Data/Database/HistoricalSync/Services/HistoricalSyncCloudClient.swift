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

    static func allowsLocalMutation() -> Bool {
        SupabaseManager.shared.allowsLocalLibraryMutation
    }

    static let live = HistoricalSyncCloudClient(
        beginAccountWork: {
            guard SupabaseManager.shared.ensureLibraryAccountOwnership() else {
                throw LibraryDetailsSyncService.LibraryTransferPersistenceError.pending
            }
            return try SupabaseManager.shared.beginUnownedAccountBoundWork()
        },
        finishAccountWork: { lease in
            SupabaseManager.shared.finishAccountBoundWork(lease)
        },
        isAccountWorkCurrent: { lease in
            SupabaseManager.shared.isAccountBoundWorkLeaseCurrent(lease)
        },
        fetchScanPage: { request in
            let data = try await SupabaseManager.shared.client
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
            return try await Self.withOwnerReviews(data)
        },
        fetchScan: { request in
            let data = try await SupabaseManager.shared.client
                .from("scans")
                .select(Self.historicalScanSelectColumns)
                .eq("user_id", value: request.userID)
                .eq("id", value: request.scanID)
                .limit(1)
                .execute()
                .data
            return try await Self.withOwnerReviews(data)
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

    /// Fetch private authority separately from the publicly readable scan projection.
    /// Require every row so a partial lookup cannot silently restore a rejected ID.
    private static func withOwnerReviews(_ data: Data) async throws -> Data {
        guard var rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw HistoricalScanPageContractError.invalidTopLevel
        }
        struct Lookup: Encodable { let p_scan_ids: [String] }
        for start in stride(from: 0, to: rows.count, by: 100) {
            let end = min(start + 100, rows.count)
            let ids = try rows[start..<end].map { row -> String in
                guard let id = row["id"] as? String else { throw HistoricalScanPageContractError.invalidTopLevel }
                return id
            }
            let response = try await SupabaseManager.shared.client.rpc("get_owned_scan_ai_reviews", params: Lookup(p_scan_ids: ids)).execute().data
            guard let reviews = try JSONSerialization.jsonObject(with: response) as? [[String: Any]] else {
                throw HistoricalScanPageContractError.invalidTopLevel
            }
            let detailResponse = try await SupabaseManager.shared.client.rpc(
                "get_owned_scan_library_details", params: Lookup(p_scan_ids: ids)
            ).execute().data
            guard let details = try JSONSerialization.jsonObject(with: detailResponse) as? [[String: Any]] else {
                throw HistoricalScanPageContractError.invalidTopLevel
            }
            for index in start..<end {
                guard let id = rows[index]["id"] as? String,
                      let review = reviews.first(where: { ($0["scan_id"] as? String)?.lowercased() == id.lowercased() }),
                      let authority = review["review"] else { throw HistoricalScanPageContractError.invalidTopLevel }
                guard let detail = details.first(where: { ($0["scan_id"] as? String)?.lowercased() == id.lowercased() }) else {
                    throw HistoricalScanPageContractError.invalidTopLevel
                }
                rows[index]["library_details"] = detail
                rows[index]["ai_identification_review"] = authority
                guard let fields = review["review_fields"] as? [String: Any] else { throw HistoricalScanPageContractError.invalidTopLevel }
                rows[index].merge(fields) { _, current in current }
            }
        }
        return try JSONSerialization.data(withJSONObject: rows)
    }

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
        "inference_tier, identification_provenance, primary_identification, custom_tags, candidates, " +
        "user_identification_override, user_confirmed_identification, " +
        "confirmed_species_id, user_review_state, confirmed_species_identity, confirmed_species_identity_revision, " +
        "image_quality_score, pet_identification, " +
        "explore_posts(id, unshared_at), " +
        "species_dictionary!scans_species_id_fkey(scientific_name, " +
        "kingdom, phylum, class, order, family, genus, wikipedia_url, " +
        "reference_image_url, hazard_type, common_names, " +
        "wikipedia_overview, iucn_red_list_status, habitat_description, " +
        "group_tags)"
}
