import CoreFoundation
import Foundation

/// The exact admitted payload is immutable; local metadata never authorizes a provider call.
struct ObservationReanalysisIntent: Sendable, Equatable {
    let ownerID: UUID
    let request: ObservationReanalysisRequest

    var identity: OfflineQueueWork.Reanalysis {
        .init(observationID: request.observationID, sourceAnalysisID: request.sourceAnalysisID,
              analysisID: request.analysisID, ownerID: ownerID)
    }

    /// Files are copied into this namespace before staging. Never reference parent-owned media.
    var photoPaths: [String] {
        request.evidence.compactMap { item in
            guard case let .image(photo) = item else { return nil }
            let suffix = photo.contentType == "image/png" ? "png" : "jpg"
            return "ReanalysisQueue/\(request.analysisID.uuidString.lowercased())/\(photo.mediaID.uuidString.lowercased()).\(suffix)"
        }
    }

    func storedData() throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1, "owner_id": ownerID.uuidString.lowercased(),
            // Preserve original bytes rather than reserializing the request on recovery.
            "request_base64": request.body.base64EncodedString()
        ], options: [.sortedKeys])
        guard data.count <= 1_400_000 else { throw MerianError.invalidResponse }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1_400_000,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == ["version", "owner_id", "request_base64"],
              let version = row["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              let ownerText = row["owner_id"] as? String, let owner = UUID(uuidString: ownerText),
              owner.uuidString.lowercased() == ownerText,
              let encoded = row["request_base64"] as? String, let body = Data(base64Encoded: encoded),
              body.base64EncodedString() == encoded else { throw MerianError.invalidResponse }
        return try Self(ownerID: owner, request: ObservationReanalysisRequest(savedBody: body))
    }
}
