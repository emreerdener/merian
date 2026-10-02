import Foundation

/// Owner review authority, independent of the immutable AI answer and species proof.
struct AIIdentificationReview: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case clear, aiRejected = "ai_rejected", awaitingAcceptance = "awaiting_acceptance" }
    struct Origin: Codable, Equatable, Sendable {
        let scientificName: String?
        let commonName: String?
        init(scientificName: String?, commonName: String?) { self.scientificName = scientificName; self.commonName = commonName }
        init(from decoder: Decoder) throws {
            try ReviewFieldKey.requireExact(decoder, keys: ["scientific_name", "common_name"])
            let values = try decoder.container(keyedBy: CodingKeys.self)
            scientificName = try values.decode(String?.self, forKey: .scientificName)
            commonName = try values.decode(String?.self, forKey: .commonName)
            guard [scientificName, commonName].allSatisfy({ ($0?.count ?? 0) <= 160 }) else { throw ConfirmedSpeciesReview.IntegrityError.invalidEnvelope }
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(scientificName, forKey: .scientificName); try values.encode(commonName, forKey: .commonName)
        }
    }
    struct Community: Codable, Equatable, Sendable {
        let request_id: String
        let rank: String
        let scientific_name: String
        let common_name: String?
        let species_id: String?
        init(from decoder: Decoder) throws {
            try ReviewFieldKey.requireExact(decoder, keys: ["request_id", "rank", "scientific_name", "common_name", "species_id"])
            let values = try decoder.container(keyedBy: CodingKeys.self)
            request_id = try values.decode(String.self, forKey: .request_id)
            rank = try values.decode(String.self, forKey: .rank)
            scientific_name = try values.decode(String.self, forKey: .scientific_name)
            common_name = try values.decode(String?.self, forKey: .common_name)
            species_id = try values.decode(String?.self, forKey: .species_id)
            guard ConfirmedSpeciesReview.Identity.isCanonicalID(request_id), ["species", "genus"].contains(rank),
                (1...160).contains(scientific_name.count), (common_name?.count ?? 0) <= 160,
                rank == "genus" ? species_id == nil : species_id.map(ConfirmedSpeciesReview.Identity.isCanonicalID) == true else {
                throw ConfirmedSpeciesReview.IntegrityError.invalidEnvelope
            }
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(request_id, forKey: .request_id); try values.encode(rank, forKey: .rank)
            try values.encode(scientific_name, forKey: .scientific_name); try values.encode(common_name, forKey: .common_name)
            try values.encode(species_id, forKey: .species_id)
        }
    }
    let community: Community?
    let version: Int
    let revision: Int
    let state: State
    let originScanID: String?
    let originIdentification: Origin?
    let operationID: String?
    let operationDigest: String?
    var isUnresolved: Bool { state != .clear }
    enum CodingKeys: String, CodingKey {
        case version, revision, state, community
        case originScanID = "origin_scan_id", originIdentification = "origin_identification"
        case operationID = "operation_id", operationDigest = "operation_digest"
    }
    init(revision: Int, state: State, originScanID: String?, originIdentification: Origin?, operationID: String? = nil, operationDigest: String? = nil, community: Community? = nil) {
        self.community = community
        version = 1; self.revision = revision; self.state = state
        self.originScanID = originScanID; self.originIdentification = originIdentification
        self.operationID = operationID; self.operationDigest = operationDigest
    }
    init(from decoder: Decoder) throws {
        try ReviewFieldKey.requireExact(decoder, keys: ["version", "revision", "state", "origin_scan_id", "origin_identification", "operation_id", "operation_digest", "community"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        community = try values.decode(Community?.self, forKey: .community)
        version = try values.decode(Int.self, forKey: .version)
        revision = try values.decode(Int.self, forKey: .revision)
        state = try values.decode(State.self, forKey: .state)
        originScanID = try values.decode(String?.self, forKey: .originScanID)
        originIdentification = try values.decode(Origin?.self, forKey: .originIdentification)
        operationID = try values.decode(String?.self, forKey: .operationID)
        operationDigest = try values.decode(String?.self, forKey: .operationDigest)
        guard version == 1, community == nil || state == .clear, (0...999_999_999).contains(revision),
              originScanID.map(ConfirmedSpeciesReview.Identity.isCanonicalID) ?? (state == .clear),
              operationID.map(ConfirmedSpeciesReview.Identity.isCanonicalID) ?? true,
              operationDigest.map({ $0.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil }) ?? true else {
            throw ConfirmedSpeciesReview.IntegrityError.invalidEnvelope
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(community, forKey: .community)
        try values.encode(version, forKey: .version); try values.encode(revision, forKey: .revision)
        try values.encode(state, forKey: .state); try values.encode(originScanID, forKey: .originScanID)
        try values.encode(originIdentification, forKey: .originIdentification)
        try values.encode(operationID, forKey: .operationID); try values.encode(operationDigest, forKey: .operationDigest)
    }
    func storedData() throws -> Data {
        let data = try JSONEncoder().encode(self)
        guard data.count <= 8_192 else { throw ConfirmedSpeciesReview.IntegrityError.invalidEnvelope }
        return data
    }
    static func restoring(_ data: Data?) throws -> Self? {
        guard let data else { return nil }
        guard data.count <= 8_192 else { throw ConfirmedSpeciesReview.IntegrityError.invalidEnvelope }
        return try JSONDecoder().decode(Self.self, from: data)
    }
    static func merging(stored: Self?, incoming: Self?) throws -> Self? {
        guard let incoming else { return stored }
        guard let stored else { return incoming }
        if incoming.revision < stored.revision { return stored }
        if incoming.revision == stored.revision && incoming != stored { throw ConfirmedSpeciesReview.IntegrityError.conflictingRevision }
        return incoming
    }
}

extension AIIdentificationReview.Origin {
    enum CodingKeys: String, CodingKey { case scientificName = "scientific_name", commonName = "common_name" }
}

extension AIIdentificationReview.Community {
    enum CodingKeys: String, CodingKey { case request_id, rank, scientific_name, common_name, species_id }
}
