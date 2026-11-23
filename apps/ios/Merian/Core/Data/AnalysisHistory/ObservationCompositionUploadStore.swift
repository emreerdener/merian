import Foundation
import SwiftData

/// Closed, held handoff only. Neither decoding nor staging grants upload or execution authority.
struct ObservationCompositionUploadWork: Equatable, Sendable {
    static let kind = "composition_evidence_upload"
    static let maximumBytes = ((CompositionSourceReservationWork.maximumBytes + 2) / 3) * 4
        + ((CompositionEvidenceUploadRequest.maximumBytes + 2) / 3) * 4 + 256
    let reservationData: Data
    let reservation: CompositionSourceReservationWork
    let request: CompositionEvidenceUploadRequest

    init(reservationData: Data, request: CompositionEvidenceUploadRequest) throws {
        let reservation = try CompositionSourceReservationWork.decode(reservationData)
        guard reservation.phase == .observed, reservation.reply?.state == .reserved else { throw MerianError.invalidResponse }
        let checked = try CompositionEvidenceUploadRequest(savedBody: request.body, input: reservation.request.input)
        guard checked == request, checked.body == (try CompositionEvidenceUploadRequest(input: reservation.request.input)).body else {
            throw MerianError.invalidResponse
        }
        self.reservationData = reservationData; self.reservation = reservation; self.request = checked
    }

    func storedData() throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "kind": Self.kind,
            "reservation_base64": reservationData.base64EncodedString(), "request_base64": request.body.base64EncodedString()],
            options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= Self.maximumBytes else { throw MerianError.invalidResponse }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= maximumBytes else { throw MerianError.invalidResponse }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data), keys: [
            "version", "kind", "reservation_base64", "request_base64"
        ])
        guard try ObservationHistoryPage.integer(row["version"]) == 1,
              row["kind"] as? String == kind else { throw MerianError.invalidResponse }
        let reservationData = try bytes(row["reservation_base64"], maximum: CompositionSourceReservationWork.maximumBytes)
        let reservation = try CompositionSourceReservationWork.decode(reservationData)
        let request = try CompositionEvidenceUploadRequest(savedBody: bytes(row["request_base64"], maximum: CompositionEvidenceUploadRequest.maximumBytes),
            input: reservation.request.input)
        return try .init(reservationData: reservationData, request: request)
    }

    private static func bytes(_ value: Any?, maximum: Int) throws -> Data {
        guard let encoded = value as? String, encoded.utf8.count <= ((maximum + 2) / 3) * 4,
              let data = Data(base64Encoded: encoded), !data.isEmpty, data.count <= maximum,
              data.base64EncodedString() == encoded else { throw MerianError.invalidResponse }
        return data
    }
}

/// Existing held V58 child only. The original reserved operation remains immutable inside the handoff.
@MainActor
enum ObservationCompositionUploadStore {
    private typealias Persistence = ObservationReanalysisPersistence
    struct Snapshot: Equatable, Sendable {
        let work: ObservationCompositionUploadWork
        let metadata: String
        let containerID: ObjectIdentifier
    }

    static func stage(_ reserved: CompositionSourceReservationStore.Snapshot,
                      proof: ObservationCompositionPreparation.Verified,
                      container: ModelContainer, isCurrent: () -> Bool,
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Snapshot {
        guard reserved.containerID == ObjectIdentifier(container),
              reserved.metadata.utf8.count <= CompositionSourceReservationWork.maximumBytes else { throw Persistence.IntegrityError.conflict }
        let request = try CompositionEvidenceUploadRequest(input: reserved.work.request.input)
        let work = try ObservationCompositionUploadWork(reservationData: Data(reserved.metadata.utf8), request: request)
        guard work.reservation == reserved.work, work.reservation.preparation == proof.preparation else { throw Persistence.IntegrityError.conflict }
        return try Persistence.transaction(proof.preparation.identity, container: container, isCurrent: isCurrent, save: save) { context in
            let (_, job, text) = try pair(proof: proof, context: context)
            if let saved = try? ObservationCompositionUploadWork.decode(Data(text.utf8)) {
                guard saved == work else { throw Persistence.IntegrityError.conflict }
                return .init(work: saved, metadata: text, containerID: ObjectIdentifier(container))
            }
            guard text == reserved.metadata else { throw Persistence.IntegrityError.conflict }
            guard let encoded = String(bytes: try work.storedData(), encoding: .utf8) else { throw Persistence.IntegrityError.conflict }
            job.metadataJSON = encoded
            return .init(work: work, metadata: encoded, containerID: ObjectIdentifier(container))
        }
    }

    /// Discovery is existing-only and cannot insert a child, job, candidate or receipt.
    static func read(proof: ObservationCompositionPreparation.Verified, container: ModelContainer,
                     isCurrent: () -> Bool) throws -> Snapshot {
        try Persistence.transaction(proof.preparation.identity, container: container, isCurrent: isCurrent,
            save: { _ in throw Persistence.IntegrityError.conflict }) { context in
                let (_, _, text) = try pair(proof: proof, context: context)
                let work = try ObservationCompositionUploadWork.decode(Data(text.utf8))
                guard work.reservation.preparation == proof.preparation else { throw Persistence.IntegrityError.conflict }
                return .init(work: work, metadata: text, containerID: ObjectIdentifier(container))
            }
    }

    // The private lookup returns the validated queue row, job and exact metadata together.
    // swiftlint:disable:next large_tuple
    private static func pair(proof: ObservationCompositionPreparation.Verified, context: ModelContext) throws -> (OfflineQueuedScan, OfflineJobRecord, String) {
        try proof.validate(context: context)
        try Persistence.requireNoResultCollision(proof.preparation.identity, context: context)
        guard let (row, job) = try Persistence.pair(proof.preparation.identity, context: context),
              let text = job.metadataJSON else { throw Persistence.IntegrityError.unavailable }
        guard text.utf8.count <= ObservationCompositionUploadWork.maximumBytes else { throw Persistence.IntegrityError.conflict }
        try ObservationCompositionPreparationStore.validateRow(proof.preparation, row: row, job: job)
        return (row, job, text)
    }
}
