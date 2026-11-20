import Foundation

/// Complete ordered identity projection only; never write or closure authority.
/// The authenticated wire decoder and persisted allocation share this validator.
struct SharedMediaNativePhotoRoleMapping: Codable, Equatable, Sendable {
    enum Role: String, Codable, Equatable, Sendable, CaseIterable { case source, ai, display }
    struct Entry: Codable, Equatable, Sendable {
        let photoOrdinal: Int
        let role: Role
        let referenceID: UUID
        let objectID: UUID
    }
    let entries: [Entry]

    func validate(_ claim: SharedMediaNativePhotoAllocation.Claim) throws {
        let references = try Self.references(claim)
        guard entries.count == references.count,
              Set(entries.map(\.objectID)).count == entries.count else { throw SharedMediaStorageFailure.conflict }
        for (index, entry) in entries.enumerated() {
            guard entry.photoOrdinal == index / 3, entry.role == Role.allCases[index % 3],
                  entry.referenceID == references[index] else { throw SharedMediaStorageFailure.conflict }
        }
    }

    /// UUIDs have fixed canonical width. Distinct placeholders reserve the exact
    /// largest mapping shape; they are never persisted or used as server IDs.
    static func reservation(_ claim: SharedMediaNativePhotoAllocation.Claim) throws -> Self {
        let references = try references(claim)
        return Self(entries: references.enumerated().map { index, reference in
            Entry(photoOrdinal: index / 3, role: Role.allCases[index % 3], referenceID: reference,
                  objectID: UUID(uuidString: String(format: "ffffffff-ffff-4fff-8fff-%012d", index))!)
        })
    }

    static func references(_ claim: SharedMediaNativePhotoAllocation.Claim) throws -> [UUID] {
        let bytes = Data(claim.candidateCanonical.utf8)
        guard bytes.count <= 1_048_576,
              SharedMediaAcquisitionEncoding.digest(Data("merian.initial-analysis.cpm-photo-candidate.v1\n".utf8) + bytes) == claim.candidateDigest,
              let candidate = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let contentText = candidate["content_canonical"] as? String else { throw MerianError.invalidResponse }
        let contentBytes = Data(contentText.utf8)
        guard SharedMediaAcquisitionEncoding.digest(Data("merian.initial-analysis.cpm-photo-content.v1\n".utf8) + contentBytes) == claim.contentDigest,
              let content = try JSONSerialization.jsonObject(with: contentBytes) as? [String: Any],
              try ObservationHistoryPage.uuid(content["scan_id"]) == claim.observationID,
              try ObservationHistoryPage.uuid(content["package_id"]) == claim.packageID,
              let photos = content["photos"] as? [[String: Any]], (1...2).contains(photos.count) else { throw MerianError.invalidResponse }
        var references: [UUID] = []
        for (index, photo) in photos.enumerated() {
            guard try ObservationHistoryPage.integer(photo["ordinal"], maximum: 1) == index else { throw MerianError.invalidResponse }
            for role in Role.allCases {
                guard let declaration = photo[role.rawValue] as? [String: Any] else { throw MerianError.invalidResponse }
                references.append(try ObservationHistoryPage.uuid(declaration["reference_id"]))
            }
        }
        guard Set(references).count == references.count else { throw MerianError.invalidResponse }
        return references
    }
}
