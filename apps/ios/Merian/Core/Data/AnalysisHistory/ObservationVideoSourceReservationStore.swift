import Foundation
import SwiftData

/// Private staged candidate only. Decoding is never upload, release or execution authority.
struct ObservationVideoSourceReservationWork: Equatable, Sendable {
    // Both independently bounded blobs may expand in base64; include fixed envelope overhead.
    static let maximumBytes = ((ObservationVideoPreparation.maximumStoredBytes + 2) / 3) * 4
        + ((ObservationVideoSourceReservationRequest.maximumBytes + 2) / 3) * 4 + 256
    static let kind = "video_source_reservation"
    let preparation: ObservationVideoPreparation
    let request: ObservationVideoSourceReservationRequest

    init(preparation: ObservationVideoPreparation, request: ObservationVideoSourceReservationRequest) throws {
        guard request.input == preparation.request.body,
              try ObservationVideoSourceReservationRequest(video: preparation.request) == request else {
            throw MerianError.invalidResponse
        }
        self.preparation = preparation; self.request = request
    }

    func storedData() throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1, "kind": Self.kind, "phase": "staged",
            "preparation_base64": try preparation.storedData(phase: .ready).base64EncodedString(),
            "candidate_base64": request.body.base64EncodedString()
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= Self.maximumBytes else { throw MerianError.invalidResponse }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= maximumBytes else { throw MerianError.invalidResponse }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data), keys: [
            "version", "kind", "phase", "preparation_base64", "candidate_base64"
        ])
        guard try ObservationHistoryPage.integer(row["version"]) == 1,
              row["kind"] as? String == kind, row["phase"] as? String == "staged" else {
            throw MerianError.invalidResponse
        }
        let saved = try ObservationVideoPreparation.decode(bytes(row["preparation_base64"], maximum: ObservationVideoPreparation.maximumStoredBytes))
        guard saved.phase == .ready else { throw MerianError.invalidResponse }
        let request = try ObservationVideoSourceReservationRequest(savedInput: saved.preparation.request.body,
            savedBody: bytes(row["candidate_base64"], maximum: ObservationVideoSourceReservationRequest.maximumBytes))
        return try .init(preparation: saved.preparation, request: request)
    }

    private static func bytes(_ value: Any?, maximum: Int) throws -> Data {
        guard let text = value as? String, text.utf8.count <= ((maximum + 2) / 3) * 4,
              let bytes = Data(base64Encoded: text), bytes.count <= maximum,
              bytes.base64EncodedString() == text else { throw MerianError.invalidResponse }
        return bytes
    }
}

/// Exact existing-child transfer. No discovery, network, claim, retry or new operation identity.
@MainActor
enum ObservationVideoSourceReservationStore {
    private typealias Persistence = ObservationReanalysisPersistence
    struct Snapshot: Equatable, Sendable {
        let work: ObservationVideoSourceReservationWork
        let metadata: String
        let containerID: ObjectIdentifier
    }

    /// Caller owns preparation/account scope and verifies the saved cohort before delivery.
    /// Replaying the same candidate does not save or rearm the held job.
    static func stage(_ request: ObservationVideoSourceReservationRequest, proof: ObservationVideoPreparation.Verified,
                      container: ModelContainer, isCurrent: () -> Bool,
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Snapshot {
        let work = try ObservationVideoSourceReservationWork(preparation: proof.preparation, request: request)
        return try Persistence.transaction(work.preparation.identity, container: container, isCurrent: isCurrent, save: save) { context in
            try proof.validate(context: context)
            try Persistence.requireNoResultCollision(work.preparation.identity, context: context)
            guard let (row, job) = try Persistence.pair(work.preparation.identity, context: context) else {
                throw Persistence.IntegrityError.unavailable
            }
            guard let text = job.metadataJSON, text.utf8.count <= ObservationVideoSourceReservationWork.maximumBytes else {
                throw Persistence.IntegrityError.conflict
            }
            if let saved = try? ObservationVideoSourceReservationWork.decode(Data(text.utf8)) {
                guard saved == work else { throw Persistence.IntegrityError.conflict }
                try ObservationVideoPreparationStore.validateRow(work.preparation, row: row, job: job)
                return .init(work: saved, metadata: text, containerID: ObjectIdentifier(container))
            }
            guard try ObservationVideoPreparationStore.restore(work.preparation, row: row, job: job) == .ready,
                  let serialized = String(data: try work.storedData(), encoding: .utf8) else { throw Persistence.IntegrityError.conflict }
            job.metadataJSON = serialized
            return .init(work: work, metadata: serialized, containerID: ObjectIdentifier(container))
        }
    }

    /// Existing-only, source-qualified recovery; missing or malformed work cannot create a job.
    static func read(proof: ObservationVideoPreparation.Verified, container: ModelContainer,
                     isCurrent: () -> Bool) throws -> Snapshot {
        try Persistence.transaction(proof.preparation.identity, container: container, isCurrent: isCurrent,
            save: { _ in throw Persistence.IntegrityError.conflict }) { context in
                try proof.validate(context: context)
                try Persistence.requireNoResultCollision(proof.preparation.identity, context: context)
                guard let (row, job) = try Persistence.pair(proof.preparation.identity, context: context),
                      let text = job.metadataJSON else { throw Persistence.IntegrityError.unavailable }
                guard text.utf8.count <= ObservationVideoSourceReservationWork.maximumBytes else { throw Persistence.IntegrityError.conflict }
                let work = try ObservationVideoSourceReservationWork.decode(Data(text.utf8))
                guard work.preparation == proof.preparation else { throw Persistence.IntegrityError.conflict }
                try ObservationVideoPreparationStore.validateRow(work.preparation, row: row, job: job)
                return .init(work: work, metadata: text, containerID: ObjectIdentifier(container))
            }
    }
}
