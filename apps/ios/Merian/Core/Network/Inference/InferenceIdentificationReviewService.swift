import Foundation
import Supabase

struct InferenceSpeciesDictionaryRecord: Decodable, Equatable, Sendable {
    let id: String
    let commonNames: [String: String?]?
    let kingdom: String?
    let phylum: String?
    let className: String?
    let order: String?
    let family: String?
    let genus: String?
    let wikipediaOverview: String?
    let hazardType: String?
    let referenceImageURL: String?
    let wikipediaURL: String?
    let iucnRedListStatus: String?
    let habitatDescription: String?
    let gbifTaxonKey: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case commonNames = "common_names"
        case kingdom
        case phylum
        case className = "class"
        case order
        case family
        case genus
        case wikipediaOverview = "wikipedia_overview"
        case hazardType = "hazard_type"
        case referenceImageURL = "reference_image_url"
        case wikipediaURL = "wikipedia_url"
        case iucnRedListStatus = "iucn_red_list_status"
        case habitatDescription = "habitat_description"
        case gbifTaxonKey = "gbif_taxon_key"
    }
}

struct InferenceIdentificationReviewMutation: Encodable, Equatable, Sendable {
    let scanID: String
    let override: String?
    let confirmed: Bool
    let confirmedSpeciesID: String?
    let userReviewState: String

    enum CodingKeys: String, CodingKey {
        case scanID = "p_scan_id"
        case override = "p_override"
        case confirmed = "p_confirmed"
        case confirmedSpeciesID = "p_confirmed_species_id"
        case userReviewState = "p_user_review_state"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scanID, forKey: .scanID)
        try container.encodeIfPresent(override, forKey: .override)
        if override == nil {
            try container.encodeNil(forKey: .override)
        }
        try container.encode(confirmed, forKey: .confirmed)
        try container.encodeIfPresent(
            confirmedSpeciesID,
            forKey: .confirmedSpeciesID
        )
        if confirmedSpeciesID == nil {
            try container.encodeNil(forKey: .confirmedSpeciesID)
        }
        try container.encode(userReviewState, forKey: .userReviewState)
    }
}

/// Account-fenced Network owner for identification-review dictionary reads and
/// the atomic review mutation RPC.
struct InferenceIdentificationReviewService {
    private let loadSpeciesHandler: @MainActor (String) async throws
        -> InferenceSpeciesDictionaryRecord?
    private let loadSpeciesIDHandler: @MainActor (String) async throws
        -> String?
    private let syncReviewHandler: @MainActor (
        InferenceIdentificationReviewMutation
    ) async throws -> Void

    init(
        loadSpecies: @escaping @MainActor (String) async throws
            -> InferenceSpeciesDictionaryRecord?,
        loadSpeciesID: @escaping @MainActor (String) async throws -> String?,
        syncReview: @escaping @MainActor (
            InferenceIdentificationReviewMutation
        ) async throws -> Void
    ) {
        loadSpeciesHandler = loadSpecies
        loadSpeciesIDHandler = loadSpeciesID
        syncReviewHandler = syncReview
    }

    @MainActor
    func loadSpecies(
        scientificName: String
    ) async throws -> InferenceSpeciesDictionaryRecord? {
        try await loadSpeciesHandler(scientificName)
    }

    @MainActor
    func loadSpeciesID(scientificName: String) async throws -> String? {
        try await loadSpeciesIDHandler(scientificName)
    }

    @MainActor
    func syncReview(
        _ mutation: InferenceIdentificationReviewMutation
    ) async throws {
        try await syncReviewHandler(mutation)
    }

    static let live = InferenceIdentificationReviewService(
        loadSpecies: { scientificName in
            try await withCurrentAccountLease {
                let rows: [InferenceSpeciesDictionaryRecord] = try await
                    SupabaseManager.shared.client
                    .from("species_dictionary")
                    .select(
                        "id, common_names, kingdom, phylum, class, order, family, genus, wikipedia_overview, hazard_type, reference_image_url, wikipedia_url, iucn_red_list_status, habitat_description, gbif_taxon_key"
                    )
                    .eq("scientific_name", value: scientificName)
                    .limit(1)
                    .execute()
                    .value
                return rows.first
            }
        },
        loadSpeciesID: { scientificName in
            try await withCurrentAccountLease {
                let rows: [SpeciesIDRow] = try await SupabaseManager.shared
                    .client
                    .from("species_dictionary")
                    .select("id")
                    .eq("scientific_name", value: scientificName)
                    .limit(1)
                    .execute()
                    .value
                return rows.first?.id
            }
        },
        syncReview: { mutation in
            try await withCurrentAccountLease {
                _ = try await SupabaseManager.shared.client
                    .rpc(
                        "update_owned_scan_identification_review",
                        params: mutation
                    )
                    .execute()
            }
        }
    )

    private struct SpeciesIDRow: Decodable {
        let id: String
    }

    @MainActor
    private static func withCurrentAccountLease<Value>(
        _ operation: @MainActor () async throws -> Value
    ) async throws -> Value {
        let manager = SupabaseManager.shared
        let lease = try manager.beginUnownedAccountBoundWork()
        defer { manager.finishAccountBoundWork(lease) }

        let value = try await operation()
        guard manager.isAccountBoundWorkLeaseCurrent(lease) else {
            throw SupabaseAuthTransitionError.signOutInProgress
        }
        return value
    }
}
