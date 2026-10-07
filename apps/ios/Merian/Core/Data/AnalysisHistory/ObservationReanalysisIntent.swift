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
    var photoPaths: [String] { Self.photoPaths(analysisID: request.analysisID, evidence: request.evidence) }

    static func photoPaths(analysisID: UUID, evidence: [ObservationReanalysisRequest.Evidence]) -> [String] {
        evidence.compactMap { item in
            guard case let .image(photo) = item else { return nil }
            let suffix = photo.contentType == "image/png" ? "png" : "jpg"
            return "ReanalysisQueue/\(analysisID.uuidString.lowercased())/\(photo.mediaID.uuidString.lowercased()).\(suffix)"
        }
    }

    func storedData() throws -> Data { try Bound(intent: self, dispatch: .ready).data() }

    static func decode(_ data: Data) throws -> Self { try Bound.decode(data).intent }

    /// Versions 2–6 belong to unbound preparation/admission. Version 1 has no
    /// durable dispatch evidence and can only recover an existing outcome.
    enum Dispatch: Sendable, Equatable {
        case legacyUnknown, ready, consumed(attempt: Int)
    }
    struct Bound: Sendable, Equatable {
        let intent: ObservationReanalysisIntent
        let dispatch: Dispatch

        func data() throws -> Data {
            let state: String, attempt: Any
            switch dispatch {
            case .legacyUnknown: throw MerianError.invalidResponse
            case .ready: state = "ready"; attempt = NSNull()
            case let .consumed(value):
                guard value > 0 else { throw MerianError.invalidResponse }
                state = "consumed"; attempt = value
            }
            let data = try JSONSerialization.data(withJSONObject: [
                "version": 7, "owner_id": intent.ownerID.uuidString.lowercased(),
                "request_base64": intent.request.body.base64EncodedString(),
                "dispatch_state": state, "dispatch_attempt": attempt
            ], options: [.sortedKeys])
            guard data.count <= 1_400_000 else { throw MerianError.invalidResponse }
            return data
        }

        static func decode(_ data: Data) throws -> Self {
            guard data.count <= 1_400_000,
                  let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = row["version"] as? NSNumber,
                  CFGetTypeID(version) != CFBooleanGetTypeID(),
                  let ownerText = row["owner_id"] as? String, let owner = UUID(uuidString: ownerText),
                  owner.uuidString.lowercased() == ownerText,
                  let encoded = row["request_base64"] as? String, let body = Data(base64Encoded: encoded),
                  body.base64EncodedString() == encoded else { throw MerianError.invalidResponse }
            let dispatch: Dispatch
            if version.doubleValue == 1 {
                guard Set(row.keys) == ["version", "owner_id", "request_base64"] else { throw MerianError.invalidResponse }
                dispatch = .legacyUnknown
            } else {
                guard version.doubleValue == 7,
                      Set(row.keys) == ["version", "owner_id", "request_base64", "dispatch_state", "dispatch_attempt"] else {
                    throw MerianError.invalidResponse
                }
                if row["dispatch_state"] as? String == "ready", row["dispatch_attempt"] is NSNull {
                    dispatch = .ready
                } else {
                    guard row["dispatch_state"] as? String == "consumed",
                          let number = row["dispatch_attempt"] as? NSNumber,
                          CFGetTypeID(number) != CFBooleanGetTypeID(),
                          let value = Int(number.stringValue), value > 0 else { throw MerianError.invalidResponse }
                    dispatch = .consumed(attempt: value)
                }
            }
            return try Self(intent: .init(ownerID: owner, request: .init(savedBody: body)), dispatch: dispatch)
        }
    }
}
