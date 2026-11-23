import Foundation

/// The original server settlement is retained separately from mutable delivery
/// acknowledgement. A replay can acknowledge it, but cannot replace its values.
struct SharedMediaCaptureFundingReceipt: Codable, Equatable, Sendable {
    static let key = "capture_funding_completion_v1"
    let version: Int
    let scanID: UUID
    let metadata: Data?
    let resolutionSHA256: String?
    var delivered: Bool

    init(scanID: UUID, settlement: InferenceResponseSettlement?, resolutionSHA256: String? = nil) throws {
        version = 1; self.scanID = scanID
        guard resolutionSHA256.map(SharedMediaAcquisitionEncoding.isHash) ?? true else {
            throw SharedMediaStorageFailure.conflict
        }
        self.resolutionSHA256 = resolutionSHA256
        if let settlement {
            guard settlement.scanId == scanID.uuidString.lowercased() else { throw SharedMediaStorageFailure.conflict }
            metadata = try Self.encodeSettlement(settlement)
        } else { metadata = nil }
        delivered = settlement == nil
    }

    func settlement(ownerID: UUID) throws -> InferenceResponseSettlement? {
        guard version == 1, metadata != nil || delivered else { throw SharedMediaStorageFailure.conflict }
        guard let metadata else { return nil }
        guard metadata.count <= 4096 else { throw SharedMediaStorageFailure.capacity }
        let dto = try JSONDecoder().decode(ScanEntitlementMetadataDTO.self, from: metadata)
        guard let value = InferenceResponseSettlement(scanId: scanID.uuidString.lowercased(), metadata: dto),
              value.accountId == ownerID, try Self.encodeSettlement(value) == metadata else { throw SharedMediaStorageFailure.conflict }
        return value
    }

    func requireReplay(_ incoming: InferenceResponseSettlement?) throws {
        // Recovery may omit entitlement metadata; use the original saved receipt.
        // Fresh response metadata may never replace that original settlement.
        if let incoming {
            guard incoming.scanId == scanID.uuidString.lowercased(),
                  try Self.encodeSettlement(incoming) == metadata else { throw SharedMediaStorageFailure.conflict }
        }
    }

    func retaining(in raw: String, replacing expected: Self? = nil) throws -> String {
        var object = try Self.object(raw)
        if let expected {
            guard try Self.read(raw) == expected else { throw SharedMediaStorageFailure.stale }
        } else if object[Self.key] != nil { throw SharedMediaStorageFailure.conflict }
        object[Self.key] = try JSONSerialization.jsonObject(with: SharedMediaAcquisitionEncoding.encode(self, maximum: 8192))
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard bytes.count <= OrdinaryInferenceCompletion.maximumBytes, let text = String(bytes: bytes, encoding: .utf8) else {
            throw SharedMediaStorageFailure.capacity
        }
        return text
    }

    static func read(_ raw: String) throws -> Self {
        let object = try object(raw)
        guard let value = object[key] else { throw SharedMediaStorageFailure.conflict }
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        let result: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: 8192)
        guard try SharedMediaAcquisitionEncoding.encode(result, maximum: 8192) == bytes,
              result.version == 1,
              result.resolutionSHA256.map(SharedMediaAcquisitionEncoding.isHash) ?? true else { throw SharedMediaStorageFailure.conflict }
        return result
    }

    private static func object(_ raw: String) throws -> [String: Any] {
        guard raw.utf8.count <= OrdinaryInferenceCompletion.maximumBytes else { throw SharedMediaStorageFailure.capacity }
        let bytes = Data(raw.utf8)
        guard let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) == bytes else { throw SharedMediaStorageFailure.conflict }
        return value
    }

    private static func encodeSettlement(_ value: InferenceResponseSettlement) throws -> Data {
        let state = value.entitlementAfter
        let object: [String: Any] = ["user_id": value.accountId.uuidString.lowercased(),
            "plan_used": value.planUsed, "credit_consumed": value.creditConsumed,
            "entitlement_after": ["current_plan": state.currentPlan, "current_tier": state.currentTier,
                "is_paid": state.isPaid, "scans_remaining": state.scansRemaining,
                "scans_available_to_start": state.scansAvailableToStart, "in_flight_count": state.inFlightCount,
                "entitlement_version": state.entitlementVersion]]
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard bytes.count <= 4096 else { throw SharedMediaStorageFailure.capacity }
        return bytes
    }
}
