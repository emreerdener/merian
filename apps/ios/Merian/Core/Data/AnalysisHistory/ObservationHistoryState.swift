import CoreFoundation
import Foundation

struct ObservationHistoryStateRequest: Encodable {
    let observation_id: String
    let analysis_id: String?
    enum CodingKeys: String, CodingKey { case schema_version, observation_id, analysis_id }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(1, forKey: .schema_version)
        try values.encode(observation_id, forKey: .observation_id)
        try values.encode(analysis_id, forKey: .analysis_id)
    }
}

/// Prepared read value only. Admission must separately fence stale revisions,
/// account/deletion changes and pending local review before changing any model.
struct ObservationHistoryState {
    let ownerID: UUID
    let observationID: UUID
    let revision: Int
    let selectedAnalysisID: UUID
    let result: ObservationHistoryPage.Result
    let reviewRevision: Int
    let review: ObservationHistoryAuthority

    static func decode(_ data: Data, request: ObservationHistoryStateRequest, ownerID: UUID) throws -> Self {
        guard data.count <= ObservationHistoryPage.maximumPageBytes else { throw ObservationHistoryError.invalidPage }
        let observation = try ObservationHistoryPage.uuid(request.observation_id)
        let target = try request.analysis_id.map { try ObservationHistoryPage.uuid($0) }
        guard target != observation else { throw ObservationHistoryError.invalidPage }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data), keys:
            ["schema_version", "owner_id", "observation_id", "state_revision", "selection_initialized", "selected_analysis_id", "analysis"])
        let selected = try ObservationHistoryPage.uuid(row["selected_analysis_id"])
        let revision = try ObservationHistoryPage.integer(row["state_revision"])
        guard try ObservationHistoryPage.integer(row["schema_version"]) == 1,
              try ObservationHistoryPage.uuid(row["owner_id"]) == ownerID,
              try ObservationHistoryPage.uuid(row["observation_id"]) == observation,
              let initialized = row["selection_initialized"] as? NSNumber,
              CFGetTypeID(initialized) == CFBooleanGetTypeID(), initialized.boolValue,
              revision > 0, selected != observation else { throw ObservationHistoryError.invalidPage }
        let item = try ObservationHistoryPage.object(row["analysis"], keys: ["snapshot", "review_revision", "review_snapshot"])
        guard let text = item["snapshot"] as? String else { throw ObservationHistoryError.invalidSnapshot }
        let bytes = Data(text.utf8)
        guard bytes.count <= LocalAnalysisRecord.maximumSnapshotBytes,
              let envelope = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw ObservationHistoryError.invalidSnapshot
        }
        let ordinal = try ObservationHistoryPage.integer(envelope["ordinal"])
        guard ordinal > 0 else { throw ObservationHistoryError.invalidSnapshot }
        let result = try ObservationHistoryPage.snapshot(bytes, observationID: request.observation_id, ordinal: ordinal)
        guard result.analysisID == (target ?? selected) else { throw ObservationHistoryError.invalidSnapshot }
        return Self(ownerID: ownerID, observationID: observation, revision: revision, selectedAnalysisID: selected,
            result: result, reviewRevision: try ObservationHistoryPage.integer(item["review_revision"]),
            review: try ObservationHistoryAuthority.decode(item["review_snapshot"]))
    }
}

/// Seven saved review fields, separate from immutable provider evidence. Legacy
/// fields remain representable without manufacturing a verified species identity.
struct ObservationHistoryAuthority {
    let aiReview: AIIdentificationReview?
    let speciesReview: ConfirmedSpeciesReview?
    let confirmedSpeciesID: String?
    let override: String?
    let confirmed: Bool?
    let state: UserReviewState?
    let identityRevision: Int
    let data: Data

    static func decode(_ value: Any?) throws -> Self {
        let row = try ObservationHistoryPage.object(value, keys: ["ai_identification_review", "confirmed_species_identity",
            "confirmed_species_identity_revision", "confirmed_species_id", "user_identification_override",
            "user_confirmed_identification", "user_review_state"])
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        guard data.count <= 32_768 else { throw ObservationHistoryError.invalidPage }
        let decoder = JSONDecoder()
        let ai = try decodeAIReview(row["ai_identification_review"]!)
        let revision = try ObservationHistoryPage.integer(row["confirmed_species_identity_revision"], maximum: 2_147_483_647)
        let speciesID = row["confirmed_species_id"] is NSNull ? nil : try ObservationHistoryPage.uuid(row["confirmed_species_id"]).uuidString.lowercased()
        let override = row["user_identification_override"] as? String
        guard row["user_identification_override"] is NSNull || (override != nil && override!.utf8.count <= 1_024) else {
            throw ObservationHistoryError.invalidPage
        }
        var confirmed: Bool?
        if !(row["user_confirmed_identification"] is NSNull) {
            guard let number = row["user_confirmed_identification"] as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID() else { throw ObservationHistoryError.invalidPage }
            confirmed = number.boolValue
        }
        let state = (row["user_review_state"] as? String).flatMap(UserReviewState.init(rawValue:))
        guard row["user_review_state"] is NSNull || state != nil else { throw ObservationHistoryError.invalidPage }
        var speciesReview: ConfirmedSpeciesReview?
        if !(row["confirmed_species_identity"] is NSNull) {
            let identity = try decoder.decode(ConfirmedSpeciesReview.Identity.self,
                from: JSONSerialization.data(withJSONObject: row["confirmed_species_identity"]!))
            guard let confirmed, let state else { throw ObservationHistoryError.invalidPage }
            speciesReview = try ConfirmedSpeciesReview(revision: revision, identity: identity,
                override: override, confirmed: confirmed, speciesID: speciesID, state: state)
        }
        return Self(aiReview: ai, speciesReview: speciesReview, confirmedSpeciesID: speciesID,
            override: override, confirmed: confirmed, state: state, identityRevision: revision, data: data)
    }

    private static func decodeAIReview(_ value: Any) throws -> AIIdentificationReview? {
        if value is NSNull { return nil }
        let data = try JSONSerialization.data(withJSONObject: value)
        guard data.count <= 8_192 else { throw ObservationHistoryError.invalidPage }
        let review = try JSONDecoder().decode(AIIdentificationReview.self, from: data)
        let names = [review.originIdentification?.scientificName, review.originIdentification?.commonName,
                     review.community?.scientific_name, review.community?.common_name]
        // Match JavaScript's contract length metric; Swift grapheme count alone
        // accepts combining-character labels that the server rejects.
        guard names.allSatisfy({ ($0?.utf16.count ?? 0) <= 160 }) else {
            throw ObservationHistoryError.invalidPage
        }
        return review
    }
}
