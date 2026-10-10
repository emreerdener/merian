import CoreFoundation
import Foundation

/// Exact ready-upload handoff. Decoding never grants dispatch or erasure authority.
struct ObservationVideoExecutionWork: Equatable, Sendable {
    static let kind = "video_execution"
    static let maximumBytes = ((ObservationVideoUploadLifecycle.maximumBytes + 2) / 3) * 4 + 512
    enum Phase: String, Sendable { case idle, running, held }
    let uploadData: Data
    let upload: ObservationVideoUploadLifecycle
    let phase: Phase
    let attemptID: UUID?
    let consumed: Bool
    var preparation: ObservationVideoPreparation { upload.staged.reservation.preparation }
    var request: ObservationVideoReanalysisRequest { preparation.request }

    init(uploadData: Data, phase: Phase = .idle, attemptID: UUID? = nil, consumed: Bool = false) throws {
        let upload = try ObservationVideoUploadLifecycle.decode(uploadData)
        guard upload.receipt?.state == .ready, upload.attempts.last?.phase == .observed,
              upload.nextMediaID == nil,
              phase == .idle ? attemptID == nil && !consumed : attemptID != nil else { throw MerianError.invalidResponse }
        if let attemptID {
            let identity = upload.staged.reservation.preparation.identity
            let reserved = upload.staged.reservation
            let occupied = [identity.ownerID, identity.observationID, identity.sourceAnalysisID, identity.analysisID]
                + upload.staged.request.inventory.items.map { $0.artifact.mediaID }
                + upload.attempts.map(\.id) + (reserved.attemptID.map { [$0] } ?? [])
            guard !occupied.contains(attemptID) else { throw MerianError.invalidResponse }
        }
        // Preserve the originally reserved input rather than regenerating a dispatch body.
        guard upload.staged.reservation.request.input == upload.staged.reservation.preparation.request.body else {
            throw MerianError.invalidResponse
        }
        self.uploadData = uploadData; self.upload = upload; self.phase = phase
        self.attemptID = attemptID; self.consumed = consumed
    }

    func requireUnexpired(at now: Date) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let raw = upload.receipt?.expiresAt, let expiry = formatter.date(from: raw), expiry > now else {
            throw MerianError.invalidResponse
        }
    }

    func storedData() throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "kind": Self.kind,
            "upload_base64": uploadData.base64EncodedString(), "phase": phase.rawValue,
            "attempt_id": attemptID.map { $0.uuidString.lowercased() as Any } ?? NSNull(), "consumed": consumed],
            options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= Self.maximumBytes else { throw MerianError.invalidResponse }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= maximumBytes else { throw MerianError.invalidResponse }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data), keys: [
            "version", "kind", "upload_base64", "phase", "attempt_id", "consumed"
        ])
        guard try ObservationHistoryPage.integer(row["version"]) == 1, row["kind"] as? String == kind,
              let encoded = row["upload_base64"] as? String,
              encoded.utf8.count <= ((ObservationVideoUploadLifecycle.maximumBytes + 2) / 3) * 4,
              let bytes = Data(base64Encoded: encoded), bytes.base64EncodedString() == encoded,
              let raw = row["phase"] as? String, let phase = Phase(rawValue: raw),
              let number = row["consumed"] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw MerianError.invalidResponse
        }
        let attempt: UUID?
        if row["attempt_id"] is NSNull { attempt = nil } else {
            let id = try ObservationHistoryPage.uuid(row["attempt_id"])
            guard row["attempt_id"] as? String == id.uuidString.lowercased() else { throw MerianError.invalidResponse }
            attempt = id
        }
        return try .init(uploadData: bytes, phase: phase, attemptID: attempt, consumed: number.boolValue)
    }
}
