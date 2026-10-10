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
        var retirement: UUID?

        func data() throws -> Data {
            let state: String, attempt: Any
            switch dispatch {
            case .legacyUnknown:
                guard retirement != nil else { throw MerianError.invalidResponse }
                state = "legacy_unknown"; attempt = NSNull()
            case .ready: state = "ready"; attempt = NSNull()
            case let .consumed(value):
                guard value > 0 else { throw MerianError.invalidResponse }
                state = "consumed"; attempt = value
            }
            var object: [String: Any] = [
                "version": retirement == nil ? 7 : 8, "owner_id": intent.ownerID.uuidString.lowercased(),
                "request_base64": intent.request.body.base64EncodedString(),
                "dispatch_state": state, "dispatch_attempt": attempt
            ]
            if let retirement {
                guard dispatch != .ready else { throw MerianError.invalidResponse }
                _ = try ObservationAnalysisRetirementRequest(operationID: retirement, execution: .init(intent.request))
                object["retirement"] = ["operation_id": retirement.uuidString.lowercased(), "state": "staged"]
            }
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
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
            var retirement: UUID?
            if version.doubleValue == 1 {
                guard Set(row.keys) == ["version", "owner_id", "request_base64"] else { throw MerianError.invalidResponse }
                dispatch = .legacyUnknown
            } else {
                var keys: Set<String> = ["version", "owner_id", "request_base64", "dispatch_state", "dispatch_attempt"]
                if version.doubleValue == 8 {
                    keys.insert("retirement")
                    guard let value = row["retirement"] as? [String: Any], Set(value.keys) == ["operation_id", "state"],
                          value["state"] as? String == "staged", let text = value["operation_id"] as? String,
                          let id = UUID(uuidString: text), id.uuidString.lowercased() == text else { throw MerianError.invalidResponse }
                    retirement = id
                }
                guard [7.0, 8.0].contains(version.doubleValue), Set(row.keys) == keys else {
                    throw MerianError.invalidResponse
                }
                if retirement != nil, row["dispatch_state"] as? String == "legacy_unknown", row["dispatch_attempt"] is NSNull {
                    dispatch = .legacyUnknown
                } else if retirement == nil, row["dispatch_state"] as? String == "ready", row["dispatch_attempt"] is NSNull {
                    dispatch = .ready
                } else {
                    guard row["dispatch_state"] as? String == "consumed",
                          let number = row["dispatch_attempt"] as? NSNumber,
                          CFGetTypeID(number) != CFBooleanGetTypeID(),
                          let value = Int(number.stringValue), value > 0 else { throw MerianError.invalidResponse }
                    dispatch = .consumed(attempt: value)
                }
            }
            let value = try Self(intent: .init(ownerID: owner, request: .init(savedBody: body)), dispatch: dispatch, retirement: retirement)
            if let retirement {
                _ = try ObservationAnalysisRetirementRequest(operationID: retirement, execution: .init(value.intent.request))
            }
            return value
        }
    }
}
