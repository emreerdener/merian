import Foundation

/// Transient inert metadata, not a Codable sidecar, request or upload permission.
/// Capability fields are private and redacted; no request factory is exposed.
struct InitialPhotoUploadTicket: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    enum Outcome: Equatable, Sendable { case held, issued }
    static let maximumBytes = 8192
    let outcome: Outcome
    let attemptID: UUID
    private let allocation: SharedMediaNativePhotoAllocation
    private let destination: InitialPhotoUploadDestination
    private let url: URL?
    private let headers: [String: String]?
    private let capabilityExpiry: Int64?
    var description: String { "InitialPhotoUploadTicket(redacted, inert)" }
    var debugDescription: String { description }

    init(data: Data, allocation: SharedMediaNativePhotoAllocation,
         destination: InitialPhotoUploadDestination, nowMilliseconds: Int64) throws {
        _ = try allocation.encoded()
        guard allocation.version == 5 || allocation.version == 9, allocation.ticketRequestStarted == true, allocation.remoteAttempt == nil,
              let receipt = allocation.receipt, let transfer = allocation.transferReservation,
              (1...8_640_000_000_000_000).contains(nowMilliseconds), data.count <= Self.maximumBytes,
              let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw MerianError.invalidResponse }
        if allocation.version == 9 {
            guard let binding = allocation.backendBinding,
                  binding.generation == destination.backendGeneration,
                  binding.configurationDigest == destination.configurationDigest else { throw MerianError.invalidResponse }
        }
        self.allocation = allocation; self.destination = destination
        let contentType = try transfer.declaredContentType(claim: allocation.claim)
        attemptID = try ObservationHistoryPage.uuid(row["attempt_id"])
        // This is a server-created write attempt, not Claim.attemptID (allocation).
        if row["outcome"] as? String == "held" {
            guard Set(row.keys) == ["outcome", "attempt_id"] else { throw MerianError.invalidResponse }
            outcome = .held; url = nil; headers = nil; capabilityExpiry = nil
            return
        }
        let keys: Set<String> = ["version", "outcome", "attempt_id", "scan_id", "assignment_digest", "object_id",
            "backend_generation", "backend_configuration_digest", "role", "byte_count", "content_type", "sha256",
            "created_at_ms", "capability_expires_at_ms", "signed_expires_at_ms", "url", "method", "headers", "provider_enforcement"]
        let contentTypeAccepted = transfer.selection.role == .source
            ? ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"].contains(contentType)
            : contentType == "image/jpeg"
        guard Set(row.keys) == keys, try ObservationHistoryPage.integer(row["version"], maximum: 1) == 1,
              row["outcome"] as? String == "issued", row["method"] as? String == "PUT",
              row["provider_enforcement"] as? String == "unqualified",
              try ObservationHistoryPage.uuid(row["scan_id"]) == allocation.claim.observationID,
              row["assignment_digest"] as? String == receipt.assignmentDigest,
              try ObservationHistoryPage.uuid(row["object_id"]) == transfer.selection.objectID,
              try ObservationHistoryPage.uuid(row["backend_generation"]) == destination.backendGeneration,
              row["backend_configuration_digest"] as? String == destination.configurationDigest,
              row["role"] as? String == transfer.selection.role.rawValue,
              try ObservationHistoryPage.integer(row["byte_count"], maximum: 33_554_432) == transfer.byteCount,
              row["content_type"] as? String == contentType,
              contentTypeAccepted, row["sha256"] as? String == transfer.sha256,
              let headers = row["headers"] as? [String: String], let rawURL = row["url"] as? String else { throw MerianError.invalidResponse }
        let maximum: Int64 = transfer.selection.role == .source ? 33_554_432 : (transfer.selection.role == .ai ? 5_242_880 : 4_194_304)
        guard transfer.byteCount > 0, transfer.byteCount <= maximum,
              headers == ["If-None-Match": "*", "Content-Type": contentType, "Content-Length": String(transfer.byteCount),
                          "Cache-Control": "private, no-store", "x-amz-content-sha256": transfer.sha256] else { throw MerianError.invalidResponse }
        let created = Int64(try ObservationHistoryPage.integer(row["created_at_ms"], maximum: 8_640_000_000_000_000))
        let expiry = Int64(try ObservationHistoryPage.integer(row["capability_expires_at_ms"], maximum: 8_640_000_000_000_000))
        let signedExpiry = Int64(try ObservationHistoryPage.integer(row["signed_expires_at_ms"], maximum: 8_640_000_000_000_000))
        guard created >= receipt.createdAtMilliseconds, created < receipt.expiresAtMilliseconds, created <= nowMilliseconds,
              expiry == min(receipt.expiresAtMilliseconds, created + 600_000), signedExpiry == (expiry / 1000) * 1000 else {
            throw MerianError.invalidResponse
        }
        url = try destination.validateSignedURL(rawURL, scan: allocation.claim.observationID, object: transfer.selection.objectID,
            created: created, signedExpiry: signedExpiry, now: nowMilliseconds)
        self.headers = headers; capabilityExpiry = expiry; outcome = .issued
    }

    func requireMatch(_ allocation: SharedMediaNativePhotoAllocation, destination: InitialPhotoUploadDestination) throws {
        guard self.allocation == allocation, self.destination == destination else { throw SharedMediaStorageFailure.stale }
    }
}
