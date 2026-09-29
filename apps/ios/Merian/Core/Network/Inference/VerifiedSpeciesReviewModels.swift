import Foundation

struct VerifiedSpeciesReviewRequest: Encodable, Equatable, Sendable {
    enum Action: String, Encodable, Sendable {
        case confirmPrimary = "confirm_primary", confirmName = "confirm_name", clear
    }
    let scanID: String
    let expectedRevision: Int
    let action: Action
    let scientificName: String?

    enum CodingKeys: String, CodingKey {
        case scanID = "scan_id"
        case expectedRevision = "expected_revision"
        case action
        case scientificName = "scientific_name"
    }

    init(mutation: InferenceIdentificationReviewMutation, revision: Int,
         primary: PrimaryIdentification) throws {
        let id = mutation.scanID.lowercased()
        guard ConfirmedSpeciesReview.Identity.isCanonicalID(id),
              (0...2_147_483_646).contains(revision), let snapshot = primary.value else {
            throw ConfirmedSpeciesReview.IntegrityError.invalidRequest
        }
        scanID = id
        expectedRevision = revision
        switch mutation.userReviewState {
        case .unreviewed:
            action = .clear
            scientificName = nil
        case .aiConfirmed:
            guard snapshot.resolution == .species else {
                throw ConfirmedSpeciesReview.IntegrityError.invalidRequest
            }
            action = .confirmPrimary
            scientificName = nil
        case .userOverridden:
            guard let name = mutation.override,
                  ConfirmedSpeciesReview.Identity.validScientificName(name) else {
                throw ConfirmedSpeciesReview.IntegrityError.invalidRequest
            }
            action = .confirmName
            scientificName = name.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        }
    }

    func validate(_ receipt: VerifiedSpeciesReviewReceipt) throws {
        guard receipt.scanID == scanID, receipt.review.revision == expectedRevision + 1,
              receipt.review.userReviewState == (action == .clear ? .unreviewed : action == .confirmPrimary ? .aiConfirmed : .userOverridden),
              (action == .clear ? receipt.review.identity == nil : receipt.review.identity != nil),
              action != .confirmName || receipt.review.userIdentificationOverride == scientificName else {
            throw ConfirmedSpeciesReview.IntegrityError.invalidEnvelope
        }
    }
}

struct VerifiedSpeciesReviewReceipt: Decodable, Equatable, Sendable {
    let scanID: String
    let review: ConfirmedSpeciesReview

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", scanID = "scan_id", review
    }

    init(from decoder: Decoder) throws {
        try ReviewFieldKey.requireExact(decoder, keys: ["schema_version", "scan_id", "review"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == 1 else {
            throw ConfirmedSpeciesReview.IntegrityError.invalidEnvelope
        }
        scanID = try values.decode(String.self, forKey: .scanID)
        review = try values.decode(ConfirmedSpeciesReview.self, forKey: .review)
        guard ConfirmedSpeciesReview.Identity.isCanonicalID(scanID) else {
            throw ConfirmedSpeciesReview.IntegrityError.invalidEnvelope
        }
        _ = try review.storedData()
    }
}

/// Presence-aware projection shared by owner history and conflict reconciliation.
/// Legacy rows have null identity/revision zero but retain legacy review semantics.
enum VerifiedSpeciesReviewProjection {
    private enum CodingKeys: String, CodingKey {
        case identity = "confirmed_species_identity"
        case revision = "confirmed_species_identity_revision"
        case override = "user_identification_override"
        case confirmed = "user_confirmed_identification"
        case speciesID = "confirmed_species_id"
        case state = "user_review_state"
    }

    static func decode(from decoder: Decoder, hasPrimary: Bool) throws -> ConfirmedSpeciesReview? {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard values.contains(.identity) || values.contains(.revision) else { return nil }
        // decode(Optional.self) requires a key, unlike decodeIfPresent.
        let identity = try values.decode(ConfirmedSpeciesReview.Identity?.self, forKey: .identity)
        let revision = try values.decode(Int.self, forKey: .revision)
        guard hasPrimary else {
            guard identity == nil, revision == 0 else { throw ConfirmedSpeciesReview.IntegrityError.invalidEnvelope }
            return nil
        }
        let review = try ConfirmedSpeciesReview(
            revision: revision, identity: identity,
            override: values.decode(String?.self, forKey: .override),
            confirmed: values.decode(Bool.self, forKey: .confirmed),
            speciesID: values.decode(String?.self, forKey: .speciesID),
            state: values.decode(UserReviewState.self, forKey: .state))
        _ = try review.storedData()
        return review
    }
}

struct VerifiedSpeciesReviewRefresh: Decodable, Sendable {
    let id: String
    let review: ConfirmedSpeciesReview
    private enum CodingKeys: String, CodingKey { case id, primary_identification, identification_provenance }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        let primary = try values.decode(PrimaryIdentificationDTO.self, forKey: .primary_identification)
        let provenance = try values.decode(IdentificationProvenanceDTO.self, forKey: .identification_provenance)
        guard PrimaryIdentification(dto: primary).value != nil,
              PrimaryIdentificationProvenancePolicy.requiresSnapshot(provenance),
              let review = try VerifiedSpeciesReviewProjection.decode(from: decoder, hasPrimary: true) else {
            throw ConfirmedSpeciesReview.IntegrityError.invalidEnvelope
        }
        self.review = review
    }
}

enum VerifiedSpeciesReviewOutcome: Equatable, Sendable {
    case acknowledged(ConfirmedSpeciesReview)
    case reconciled(ConfirmedSpeciesReview)

    var review: ConfirmedSpeciesReview {
        switch self { case .acknowledged(let review), .reconciled(let review): return review }
    }
}
