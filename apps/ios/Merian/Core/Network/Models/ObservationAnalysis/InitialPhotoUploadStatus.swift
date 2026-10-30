import CoreFoundation
import Foundation

/// Inactive observation decoder. No persistence, PUT, closure or release authority.
/// The caller supplies its exact validated allocation and role object, never a
/// replacement tuple from the response. Historical expiry is not a read cutoff.
struct InitialPhotoUploadStatus: Equatable, Sendable {
    enum State: String, Sendable { case bound, mayHaveIssued = "may_have_issued" }
    struct Attempt: Equatable, Sendable {
        let id: UUID
        let state: State
        let createdAtMilliseconds: Int64, capabilityExpiresAtMilliseconds: Int64
        let writeClosed: Bool
    }
    static let maximumBytes = 2048
    let attempt: Attempt?
    private let ownerID: UUID, scanID: UUID, objectID: UUID
    private let receipt: SharedMediaNativePhotoAllocation.Receipt

    init(data: Data, allocation: SharedMediaNativePhotoAllocation, objectID: UUID,
         saved: Self? = nil) throws {
        _ = try allocation.encoded()
        guard let receipt = allocation.receipt, let mapping = allocation.roleMapping,
              mapping.entries.contains(where: { $0.objectID == objectID }),
              data.count <= Self.maximumBytes,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == ["version", "authority", "scan_id", "assignment_digest", "object_id", "attempt"],
              try ObservationHistoryPage.integer(row["version"], maximum: 1) == 1,
              row["authority"] as? String == "none",
              try ObservationHistoryPage.uuid(row["scan_id"]) == allocation.claim.observationID,
              row["assignment_digest"] as? String == receipt.assignmentDigest,
              try ObservationHistoryPage.uuid(row["object_id"]) == objectID else { throw MerianError.invalidResponse }
        ownerID = allocation.claim.profile.ownerID; scanID = allocation.claim.observationID
        self.objectID = objectID; self.receipt = receipt
        if row["attempt"] is NSNull { attempt = nil } else {
            guard let value = row["attempt"] as? [String: Any],
                  Set(value.keys) == ["attempt_id", "state", "created_at_ms", "capability_expires_at_ms", "write_closed"],
                  let rawState = value["state"] as? String, let state = State(rawValue: rawState),
                  let closed = value["write_closed"] as? NSNumber,
                  CFGetTypeID(closed) == CFBooleanGetTypeID() else { throw MerianError.invalidResponse }
            let created = Int64(try ObservationHistoryPage.integer(value["created_at_ms"], maximum: 8_640_000_000_000_000))
            let expires = Int64(try ObservationHistoryPage.integer(value["capability_expires_at_ms"], maximum: 8_640_000_000_000_000))
            guard created >= receipt.createdAtMilliseconds, created < receipt.expiresAtMilliseconds,
                  expires == min(receipt.expiresAtMilliseconds, created + 600_000),
                  !closed.boolValue || state == .mayHaveIssued else { throw MerianError.invalidResponse }
            attempt = .init(id: try ObservationHistoryPage.uuid(value["attempt_id"]), state: state,
                            createdAtMilliseconds: created, capabilityExpiresAtMilliseconds: expires, writeClosed: closed.boolValue)
        }
        if let saved {
            guard saved.ownerID == ownerID, saved.scanID == scanID, saved.objectID == objectID,
                  saved.receipt == receipt else { throw MerianError.invalidResponse }
            if let old = saved.attempt {
                guard let attempt, attempt.id == old.id,
                      attempt.createdAtMilliseconds == old.createdAtMilliseconds,
                      attempt.capabilityExpiresAtMilliseconds == old.capabilityExpiresAtMilliseconds,
                      old.state != .mayHaveIssued || attempt.state == old.state,
                      !old.writeClosed || attempt.writeClosed else { throw MerianError.invalidResponse }
            }
        }
    }
}
