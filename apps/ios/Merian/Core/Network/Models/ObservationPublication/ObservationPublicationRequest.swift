import Foundation

/// Immutable consent. The durable caller creates the operation ID before saving or sending.
struct ObservationPublicationRequest: Encodable, Equatable, Sendable {
    let operationID: UUID
    let observationID: UUID
    let analysisID: UUID
    let expectedObservationRevision: Int
    let expectedReviewRevision: Int
    let taxonomyVersionID: UUID
    let initialTaxonID: UUID?
    let note: String?
    let mediaIDs: [UUID]

    init(operationID: UUID, observationID: UUID, analysisID: UUID,
         expectedObservationRevision: Int, expectedReviewRevision: Int,
         taxonomyVersionID: UUID, initialTaxonID: UUID?, note: String?, mediaIDs: [UUID]) throws {
        guard (0...2_147_483_646).contains(expectedObservationRevision),
              (0...2_147_483_646).contains(expectedReviewRevision),
              (1...6).contains(mediaIDs.count), Set(mediaIDs).count == mediaIDs.count,
              note.map({ $0.unicodeScalars.count <= 1000 }) ?? true else { throw MerianError.invalidResponse }
        self.operationID = operationID; self.observationID = observationID; self.analysisID = analysisID
        self.expectedObservationRevision = expectedObservationRevision; self.expectedReviewRevision = expectedReviewRevision
        self.taxonomyVersionID = taxonomyVersionID; self.initialTaxonID = initialTaxonID
        self.note = note; self.mediaIDs = mediaIDs
        guard try JSONEncoder().encode(self).count <= 3800 else { throw MerianError.invalidResponse }
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schema_version, operation_id, observation_id, analysis_id
        case expected_observation_revision, expected_review_revision
        case taxonomy_version_id, initial_taxon_id, note, media_ids
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(1, forKey: .schema_version)
        try values.encode(operationID.uuidString.lowercased(), forKey: .operation_id)
        try values.encode(observationID.uuidString.lowercased(), forKey: .observation_id)
        try values.encode(analysisID.uuidString.lowercased(), forKey: .analysis_id)
        try values.encode(expectedObservationRevision, forKey: .expected_observation_revision)
        try values.encode(expectedReviewRevision, forKey: .expected_review_revision)
        try values.encode(taxonomyVersionID.uuidString.lowercased(), forKey: .taxonomy_version_id)
        try values.encode(initialTaxonID?.uuidString.lowercased(), forKey: .initial_taxon_id)
        try values.encode(note, forKey: .note)
        try values.encode(mediaIDs.map { $0.uuidString.lowercased() }, forKey: .media_ids)
    }

    /// Strict restoration for a future durable outbox; missing optional keys are not consent.
    static func decode(_ data: Data) throws -> Self {
        let row = try ObservationPublicationWire.object(data, keys: Set(CodingKeys.allCases.map(\.rawValue)))
        guard try ObservationPublicationWire.integer(row["schema_version"]) == 1,
              let media = row["media_ids"] as? [Any], (1...6).contains(media.count),
              row["note"] is NSNull || row["note"] is String else { throw MerianError.invalidResponse }
        return try Self(operationID: ObservationPublicationWire.uuid(row["operation_id"]),
            observationID: ObservationPublicationWire.uuid(row["observation_id"]),
            analysisID: ObservationPublicationWire.uuid(row["analysis_id"]),
            expectedObservationRevision: ObservationPublicationWire.integer(row["expected_observation_revision"]),
            expectedReviewRevision: ObservationPublicationWire.integer(row["expected_review_revision"]),
            taxonomyVersionID: ObservationPublicationWire.uuid(row["taxonomy_version_id"]),
            initialTaxonID: row["initial_taxon_id"] is NSNull ? nil : ObservationPublicationWire.uuid(row["initial_taxon_id"]),
            note: row["note"] as? String, mediaIDs: media.map { try ObservationPublicationWire.uuid($0) })
    }

    var statusRequest: ObservationPublicationStatusRequest {
        .init(operationID: operationID, observationID: observationID, analysisID: analysisID)
    }
}

struct ObservationPublicationStatusRequest: Encodable, Equatable, Sendable {
    let operationID: UUID
    let observationID: UUID
    /// Local expectation only; the status endpoint does not accept this field.
    let analysisID: UUID
    enum CodingKeys: String, CodingKey { case schema_version, operation_id, observation_id }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(1, forKey: .schema_version)
        try values.encode(operationID.uuidString.lowercased(), forKey: .operation_id)
        try values.encode(observationID.uuidString.lowercased(), forKey: .observation_id)
    }
}

/// Discovery never supplies consent or invents an operation identity.
struct ObservationPublicationTargetRequest: Encodable, Equatable, Sendable {
    let observationID: UUID
    enum CodingKeys: String, CodingKey { case schema_version, observation_id }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(1, forKey: .schema_version)
        try values.encode(observationID.uuidString.lowercased(), forKey: .observation_id)
    }
}
