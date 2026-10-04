import Foundation

/// Immutable content reference. Delivery URLs and storage keys are never persisted.
struct ObservationHistoryPhotoReference: Equatable, Sendable {
    let mediaID: UUID
    let contentType: String
    let byteCount: Int
    let sha256: String
    static let maximumBytes = 32 * 1024 * 1024

    static func decodeManifest(_ value: Any?, observationID: UUID, analysisID: UUID) throws -> [Self] {
        let manifest = try ObservationHistoryPage.object(value, keys: ["schema_version", "items"])
        guard try ObservationHistoryPage.integer(manifest["schema_version"]) == 2,
              let items = manifest["items"] as? [[String: Any]], (1...64).contains(items.count) else {
            throw ObservationHistoryError.invalidSnapshot
        }
        var photos: [Self] = [], seen = Set<UUID>(), total = 0
        for item in items {
            if item["kind"] as? String == "description" {
                _ = try ObservationHistoryPage.object(item, keys: ["kind", "text"])
                guard let text = item["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      text.unicodeScalars.count <= 8192 else { throw ObservationHistoryError.invalidSnapshot }
                continue
            }
            _ = try ObservationHistoryPage.object(item, keys: ["kind", "media_id", "content_type", "byte_count", "sha256"])
            let id = try ObservationHistoryPage.uuid(item["media_id"])
            let count = try ObservationHistoryPage.integer(item["byte_count"], maximum: maximumBytes)
            guard item["kind"] as? String == "image", id != observationID, id != analysisID, seen.insert(id).inserted,
                  let type = item["content_type"] as? String, ["image/jpeg", "image/png", "image/heic"].contains(type), count > 0,
                  let hash = item["sha256"] as? String, hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                throw ObservationHistoryError.invalidSnapshot
            }
            total += count
            guard total <= maximumBytes else { throw ObservationHistoryError.invalidSnapshot }
            photos.append(Self(mediaID: id, contentType: type, byteCount: count, sha256: hash))
        }
        guard !photos.isEmpty else { throw ObservationHistoryError.invalidSnapshot }
        return photos
    }
}
