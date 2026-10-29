import Foundation

/// Inactive v2 metadata decoder. No request, persistence, transfer or closure
/// authority follows from this projection. The receiving owner must reserve
/// metadata/revision runway before requesting or saving an enriched receipt.
enum InitialPhotoAllocationRoleReply: Equatable, Sendable {
    typealias Role = SharedMediaNativePhotoRoleMapping.Role
    typealias Entry = SharedMediaNativePhotoRoleMapping.Entry
    struct Projection: Equatable, Sendable {
        let receipt: SharedMediaNativePhotoAllocation.Receipt
        let entries: [Entry]
    }
    static let maximumBytes = 2048
    case allocated(Projection)
    case held(InitialPhotoAllocationReply.HeldReason)

    init(data: Data, request: InitialPhotoAllocationRequest, saved: Projection? = nil) throws {
        guard data.count <= Self.maximumBytes,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MerianError.invalidResponse
        }
        try InitialPhotoAllocationReply.requireAssociation(row, request: request, version: 2)
        let common = InitialPhotoAllocationReply.associationKeys
        switch row["outcome"] as? String {
        case "terminal_held":
            guard Set(row.keys) == common.union(["reason"]), let reason = row["reason"] as? String,
                  let held = InitialPhotoAllocationReply.HeldReason(rawValue: reason) else { throw MerianError.invalidResponse }
            // A hold cannot discard a previously saved projection or prove closure.
            self = .held(held)
        case "allocated":
            guard Set(row.keys) == common.union(["assignment_digest", "created_at_ms", "expires_at_ms", "role_mapping"]),
                  let digest = row["assignment_digest"] as? String,
                  let mapping = row["role_mapping"] as? [[String: Any]] else { throw MerianError.invalidResponse }
            let receipt = try InitialPhotoAllocationReply.receipt(row, digest: digest, request: request)
            let references = try SharedMediaNativePhotoRoleMapping.references(request.allocation.claim)
            guard mapping.count == references.count else { throw MerianError.invalidResponse }
            var objects = Set<UUID>(), entries: [Entry] = []
            for (index, value) in mapping.enumerated() {
                guard Set(value.keys) == ["photo_ordinal", "role", "reference_id", "object_id"],
                      try ObservationHistoryPage.integer(value["photo_ordinal"], maximum: 1) == index / 3,
                      value["role"] as? String == Role.allCases[index % 3].rawValue,
                      try ObservationHistoryPage.uuid(value["reference_id"]) == references[index] else { throw MerianError.invalidResponse }
                let object = try ObservationHistoryPage.uuid(value["object_id"])
                guard objects.insert(object).inserted else { throw MerianError.invalidResponse }
                entries.append(.init(photoOrdinal: index / 3, role: Role.allCases[index % 3], referenceID: references[index], objectID: object))
            }
            let projection = Projection(receipt: receipt, entries: entries)
            guard saved == nil || saved == projection else { throw MerianError.invalidResponse }
            self = .allocated(projection)
        default: throw MerianError.invalidResponse
        }
    }

}
