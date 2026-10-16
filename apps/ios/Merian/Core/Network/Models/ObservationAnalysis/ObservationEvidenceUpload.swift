import CryptoKit
import Foundation

/// Stable IDs and owned bytes come from durable capture. This value never mints retry identities.
struct ObservationEvidenceUpload: Sendable {
    struct Photo: Sendable {
        let mediaID: UUID
        let contentType: String
        let bytes: Data
    }
    struct Reference: Equatable, Sendable, Encodable {
        let mediaID: UUID
        let contentType: String
        let byteCount: Int
        let sha256: String
        enum CodingKeys: String, CodingKey { case kind, media_id, content_type, byte_count, sha256 }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode("image", forKey: .kind)
            try values.encode(mediaID.uuidString.lowercased(), forKey: .media_id)
            try values.encode(contentType, forKey: .content_type)
            try values.encode(byteCount, forKey: .byte_count)
            try values.encode(sha256, forKey: .sha256)
        }
    }
    let observationID: UUID
    let analysisID: UUID
    let photos: [Photo]
    static let maximumBytes = 5 * 1024 * 1024

    init(observationID: UUID, analysisID: UUID, photos: [Photo]) throws {
        guard observationID != analysisID, (1...5).contains(photos.count) else { throw MerianError.invalidResponse }
        var seen = Set<UUID>(), total = 0
        for photo in photos {
            guard seen.insert(photo.mediaID).inserted,
                  photo.mediaID != observationID, photo.mediaID != analysisID,
                  ["image/jpeg", "image/png"].contains(photo.contentType),
                  !photo.bytes.isEmpty, photo.bytes.count <= Self.maximumBytes - total else {
                throw MerianError.invalidResponse
            }
            total += photo.bytes.count
        }
        self.observationID = observationID; self.analysisID = analysisID; self.photos = photos
    }

    struct Prepared: Sendable {
        let observationID: UUID
        let analysisID: UUID
        let body: Data
        let references: [Reference]
    }

    /// Called off the main actor by the endpoint's existing preparation task owner.
    func prepare() throws -> Prepared {
        try Task.checkCancellation()
        let metadata: [String: Any] = ["schema_version": 1,
            "observation_id": observationID.uuidString.lowercased(),
            "analysis_id": analysisID.uuidString.lowercased(),
            "photos": photos.map { ["media_id": $0.mediaID.uuidString.lowercased(),
                                     "content_type": $0.contentType, "byte_count": $0.bytes.count] as [String: Any] }]
        let header = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        guard (1...4096).contains(header.count) else { throw MerianError.invalidResponse }
        let count = UInt32(header.count)
        var body = Data([UInt8((count >> 24) & 255), UInt8((count >> 16) & 255), UInt8((count >> 8) & 255), UInt8(count & 255)])
        body.append(header)
        var references: [Reference] = []
        for photo in photos {
            try Task.checkCancellation()
            body.append(photo.bytes)
            references.append(Reference(mediaID: photo.mediaID, contentType: photo.contentType, byteCount: photo.bytes.count,
                sha256: SHA256.hash(data: photo.bytes).map { String(format: "%02x", $0) }.joined()))
        }
        try Task.checkCancellation()
        return Prepared(observationID: observationID, analysisID: analysisID, body: body, references: references)
    }
}

struct ObservationEvidenceUploadReceipt: Equatable, Sendable {
    let observationID: UUID
    let analysisID: UUID
    let items: [ObservationEvidenceUpload.Reference]

    static func decode(_ data: Data, request: ObservationEvidenceUpload.Prepared) throws -> Self {
        guard data.count <= 4096,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == ["schema_version", "observation_id", "analysis_id", "items"],
              exactInteger(row["schema_version"], equals: 1),
              row["observation_id"] as? String == request.observationID.uuidString.lowercased(),
              row["analysis_id"] as? String == request.analysisID.uuidString.lowercased(),
              let items = row["items"] as? [[String: Any]], items.count == request.references.count else {
            throw MerianError.invalidResponse
        }
        for (item, expected) in zip(items, request.references) {
            guard Set(item.keys) == ["kind", "media_id", "content_type", "byte_count", "sha256"],
                  item["kind"] as? String == "image",
                  item["media_id"] as? String == expected.mediaID.uuidString.lowercased(),
                  item["content_type"] as? String == expected.contentType,
                  exactInteger(item["byte_count"], equals: expected.byteCount),
                  item["sha256"] as? String == expected.sha256 else { throw MerianError.invalidResponse }
        }
        return Self(observationID: request.observationID, analysisID: request.analysisID, items: request.references)
    }

    private static func exactInteger(_ value: Any?, equals expected: Int) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
        return number.doubleValue == Double(expected)
    }
}
