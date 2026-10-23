import Foundation

/// Leaf canonical dispatch only. A decoded slot does not establish receiving
/// row joins, current target state, physical availability or mutation authority.
enum SharedMediaNativeReceivingSlot {
    typealias Intent = SharedMediaNativeReceivingIntent
    case prepared(Intent.Prepared)
    case received(Intent.Prepared, Intent.Received, Intent.Transaction)
    case abandoned(Intent.Abandoned)

    static func decode(_ row: SharedMediaNativeReceivingIntentGraph.Row,
                       profile: SharedMediaNativeAppProfile) throws -> Self {
        try row.requireNoReleaseStart()
        guard row.cursor == row.id.uuidString.lowercased(),
              row.inventoryID == profile.inventoryID, row.inventoryGeneration == profile.generation,
              row.ownerID == profile.ownerID, row.revision >= 0,
              SharedMediaAcquisitionEncoding.isHash(row.preparedSHA256) else {
            throw SharedMediaStorageFailure.conflict
        }
        if row.phase == "abandoned" {
            guard row.preparedData == nil, let bytes = row.resultData,
                  row.resultSHA256 == SharedMediaAcquisitionEncoding.digest(bytes) else {
                throw SharedMediaStorageFailure.conflict
            }
            let result = try Intent.Abandoned.decode(bytes)
            guard row.version == result.version, row.revision == result.revision,
                  row.preparedSHA256 == result.preparedSHA256, result.profile == profile,
                  result.package.id == row.id, result.package.generation == row.draftGeneration,
                  result.operationID == row.operationID else { throw SharedMediaStorageFailure.conflict }
            return .abandoned(result)
        }
        guard let bytes = row.preparedData, row.preparedSHA256 == SharedMediaAcquisitionEncoding.digest(bytes) else {
            throw SharedMediaStorageFailure.conflict
        }
        let prepared = try Intent.Prepared.decode(bytes)
        guard row.version == prepared.version, prepared.profile == profile,
              prepared.package.id == row.id, prepared.package.generation == row.draftGeneration,
              prepared.operationID == row.operationID else { throw SharedMediaStorageFailure.conflict }
        let revision = prepared.intentRevision ?? 0
        switch row.phase {
        case "prepared":
            guard row.revision == revision, row.resultData == nil, row.resultSHA256 == nil else {
                throw SharedMediaStorageFailure.conflict
            }
            return .prepared(prepared)
        case "received":
            // V1 receipt decoding preserves historical values, but this new
            // durable slot owner only executes fresh P2 submissions.
            guard prepared.version == 2, row.revision == (try SharedMediaStoragePolicy.add(revision, 1)),
                  let bytes = row.resultData, row.resultSHA256 == SharedMediaAcquisitionEncoding.digest(bytes) else {
                throw SharedMediaStorageFailure.conflict
            }
            let result = try Intent.Received.decode(bytes, prepared: prepared)
            return .received(prepared, result, try result.reconstruct(prepared))
        default: throw SharedMediaStorageFailure.closed
        }
    }
}
