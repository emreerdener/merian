import Foundation

/// Reads candidates for an explicit historical analysis; creates no operation or consent.
struct ObservationPublicationConsentRequest: Encodable, Equatable, Sendable {
    let observationID: UUID
    let analysisID: UUID
    enum CodingKeys: String, CodingKey { case schema_version, observation_id, analysis_id }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(1, forKey: .schema_version)
        try values.encode(observationID.uuidString.lowercased(), forKey: .observation_id)
        try values.encode(analysisID.uuidString.lowercased(), forKey: .analysis_id)
    }
}

/// Immutable descriptive snapshot. Neither candidate presence nor preflight success proves ready media.
struct ObservationPublicationConsentSnapshot: Equatable, Sendable {
    struct Photo: Equatable, Sendable {
        let mediaID: UUID
        let contentType: String
        let byteCount: Int
        let sha256: String
    }
    let observationID: UUID
    let analysisID: UUID
    let expectedObservationRevision: Int
    let expectedReviewRevision: Int
    let taxonomyVersionID: UUID
    /// The preflight contract always returns null. No name matching invents a taxonomy node.
    let initialTaxonID: UUID? = nil
    let media: [Photo]
    private init(request: ObservationPublicationConsentRequest, observationRevision: Int,
                 reviewRevision: Int, taxonomyVersionID: UUID, media: [Photo]) {
        observationID = request.observationID; analysisID = request.analysisID
        expectedObservationRevision = observationRevision; expectedReviewRevision = reviewRevision
        self.taxonomyVersionID = taxonomyVersionID; self.media = media
    }

    static func decode(_ data: Data, request: ObservationPublicationConsentRequest) throws -> Self {
        // Keep the existing admission/status 4 KiB decoder unchanged. This separate
        // owner response can describe all 64 immutable candidates before a user chooses 1–6.
        guard data.count <= 32 * 1024,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MerianError.invalidResponse
        }
        let row = try object(root, keys: ["schema_version", "observation_id", "analysis_id",
            "expected_observation_revision", "expected_review_revision", "taxonomy_version_id", "initial_taxon_id", "media"])
        guard try ObservationPublicationWire.integer(row["schema_version"]) == 1,
              try ObservationPublicationWire.uuid(row["observation_id"]) == request.observationID,
              try ObservationPublicationWire.uuid(row["analysis_id"]) == request.analysisID,
              row["initial_taxon_id"] is NSNull,
              let values = row["media"] as? [[String: Any]], (1...64).contains(values.count) else {
            throw MerianError.invalidResponse
        }
        var media: [Photo] = [], seen = Set<UUID>(), total = 0
        let maximumBytes = 32 * 1024 * 1024
        for value in values {
            let photo = try object(value, keys: ["media_id", "content_type", "byte_count", "sha256"])
            let id = try ObservationPublicationWire.uuid(photo["media_id"])
            let count = try ObservationPublicationWire.integer(photo["byte_count"])
            guard seen.insert(id).inserted, (1...maximumBytes).contains(count),
                  total <= maximumBytes - count,
                  let type = photo["content_type"] as? String, ["image/jpeg", "image/png", "image/heic"].contains(type),
                  let hash = photo["sha256"] as? String, hash.utf8.count == 64,
                  hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw MerianError.invalidResponse
            }
            total += count
            media.append(Photo(mediaID: id, contentType: type, byteCount: count, sha256: hash))
        }
        return try Self(request: request,
            observationRevision: ObservationPublicationWire.integer(row["expected_observation_revision"]),
            reviewRevision: ObservationPublicationWire.integer(row["expected_review_revision"]),
            taxonomyVersionID: ObservationPublicationWire.uuid(row["taxonomy_version_id"]), media: media)
    }

    private static func object(_ row: [String: Any], keys: Set<String>) throws -> [String: Any] {
        guard Set(row.keys) == keys else { throw MerianError.invalidResponse }
        return row
    }
}
