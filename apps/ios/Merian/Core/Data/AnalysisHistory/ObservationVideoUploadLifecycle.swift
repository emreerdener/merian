import Foundation
import SwiftData

/// Bounded append-only upload evidence. Unknown work never grants another dispatch.
struct ObservationVideoUploadLifecycle: Equatable, Sendable {
    enum Phase: String, Sendable { case running, unknown, observed }
    struct Attempt: Equatable, Sendable {
        let id: UUID
        let mediaID: UUID
        let phase: Phase
        let receipt: ObservationVideoEvidenceReceipt?
    }
    static let maximumBytes = ((ObservationVideoUploadWork.maximumBytes + 2) / 3) * 4
        + 7 * (((ObservationVideoEvidenceReceipt.maximumBytes + 2) / 3) * 4 + 256) + 256
    let stagedData: Data
    let staged: ObservationVideoUploadWork
    let attempts: [Attempt]
    var receipt: ObservationVideoEvidenceReceipt? { attempts.last(where: { $0.receipt != nil })?.receipt }
    var nextMediaID: UUID? {
        guard attempts.last?.phase == .observed || attempts.isEmpty else { return nil }
        return staged.request.inventory.items.first { item in
            receipt?.items.first(where: { $0.metadata.artifact.mediaID == item.artifact.mediaID })?.readyAt == nil
        }?.artifact.mediaID
    }

    init(stagedData: Data, attempts: [Attempt] = []) throws {
        let staged = try ObservationVideoUploadWork.decode(stagedData)
        guard attempts.count <= staged.request.inventory.items.count else { throw MerianError.invalidResponse }
        var previous: ObservationVideoEvidenceReceipt?
        var ids = Set([staged.reservation.preparation.identity.ownerID, staged.request.identity.observationID,
            staged.request.identity.sourceAnalysisID, staged.request.identity.analysisID]
            + staged.request.inventory.items.map { $0.artifact.mediaID })
        if let id = staged.reservation.attemptID { ids.insert(id) }
        for (index, attempt) in attempts.enumerated() {
            guard ids.insert(attempt.id).inserted,
                  let next = staged.request.inventory.items.first(where: { item in
                      previous?.items.first(where: { $0.metadata.artifact.mediaID == item.artifact.mediaID })?.readyAt == nil
                  }), next.artifact.mediaID == attempt.mediaID else { throw MerianError.invalidResponse }
            if attempt.phase == .observed {
                guard let receipt = attempt.receipt else { throw MerianError.invalidResponse }
                let checked = try ObservationVideoEvidenceReceipt(data: receipt.data, request: staged.request,
                    ownerID: staged.reservation.preparation.identity.ownerID, previous: previous)
                guard checked == receipt, checked.items.contains(where: { $0.metadata.artifact.mediaID == attempt.mediaID && $0.readyAt != nil }) else {
                    throw MerianError.invalidResponse
                }
                previous = checked
            } else {
                guard index == attempts.count - 1, attempt.receipt == nil else { throw MerianError.invalidResponse }
            }
        }
        self.stagedData = stagedData; self.staged = staged; self.attempts = attempts
    }

    func storedData() throws -> Data {
        if attempts.isEmpty { return stagedData }
        let rows: [[String: Any]] = attempts.map { ["attempt_id": $0.id.uuidString.lowercased(),
            "media_id": $0.mediaID.uuidString.lowercased(), "phase": $0.phase.rawValue,
            "receipt_base64": $0.receipt.map { $0.data.base64EncodedString() as Any } ?? NSNull()] }
        let data = try JSONSerialization.data(withJSONObject: ["version": 2, "kind": ObservationVideoUploadWork.kind,
            "staged_base64": stagedData.base64EncodedString(), "attempts": rows], options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= Self.maximumBytes else { throw MerianError.invalidResponse }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= maximumBytes else { throw MerianError.invalidResponse }
        guard let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MerianError.invalidResponse }
        if try ObservationHistoryPage.integer(row["version"]) == 1 { return try .init(stagedData: data) }
        guard try ObservationHistoryPage.integer(row["version"]) == 2,
              Set(row.keys) == ["version", "kind", "staged_base64", "attempts"], row["kind"] as? String == ObservationVideoUploadWork.kind,
              let rows = row["attempts"] as? [[String: Any]], !rows.isEmpty, rows.count <= 7 else { throw MerianError.invalidResponse }
        let stagedData = try bytes(row["staged_base64"], maximum: ObservationVideoUploadWork.maximumBytes)
        let staged = try ObservationVideoUploadWork.decode(stagedData)
        let attempts: [Attempt] = try rows.map { row in
            guard Set(row.keys) == ["attempt_id", "media_id", "phase", "receipt_base64"],
                  let raw = row["phase"] as? String, let phase = Phase(rawValue: raw) else { throw MerianError.invalidResponse }
            let id = try ObservationHistoryPage.uuid(row["attempt_id"]), mediaID = try ObservationHistoryPage.uuid(row["media_id"])
            guard row["attempt_id"] as? String == id.uuidString.lowercased(), row["media_id"] as? String == mediaID.uuidString.lowercased() else { throw MerianError.invalidResponse }
            let receipt: ObservationVideoEvidenceReceipt?
            if row["receipt_base64"] is NSNull { receipt = nil } else {
                receipt = try .init(data: bytes(row["receipt_base64"], maximum: ObservationVideoEvidenceReceipt.maximumBytes),
                    request: staged.request, ownerID: staged.reservation.preparation.identity.ownerID)
            }
            return .init(id: id, mediaID: mediaID, phase: phase, receipt: receipt)
        }
        return try .init(stagedData: stagedData, attempts: attempts)
    }

    private static func bytes(_ value: Any?, maximum: Int) throws -> Data {
        guard let text = value as? String, text.utf8.count <= ((maximum + 2) / 3) * 4,
              let data = Data(base64Encoded: text), !data.isEmpty, data.count <= maximum,
              data.base64EncodedString() == text else { throw MerianError.invalidResponse }
        return data
    }
}

@MainActor
enum ObservationVideoUploadLifecycleStore {
    private typealias Persistence = ObservationReanalysisPersistence
    private typealias Work = ObservationVideoUploadLifecycle
    struct Snapshot: Equatable, Sendable {
        let work: ObservationVideoUploadLifecycle
        let metadata: String
        let containerID: ObjectIdentifier
    }
    struct Claim: Sendable {
        let snapshot: Snapshot
        fileprivate init(_ snapshot: Snapshot) { self.snapshot = snapshot }
    }
    static func read(proof: ObservationVideoPreparation.Verified, container: ModelContainer, isCurrent: () -> Bool) throws -> Snapshot {
        try Persistence.transaction(proof.preparation.identity, container: container, isCurrent: isCurrent,
            save: { _ in throw Persistence.IntegrityError.conflict }) { context in
                try pair(proof, container, context).snapshot
            }
    }
    static func claim(_ expected: Snapshot, proof: ObservationVideoPreparation.Verified, container: ModelContainer,
                      isCurrent: () -> Bool, attemptID: UUID = UUID(), now: Date = Date(), save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Claim {
        guard expected.containerID == ObjectIdentifier(container), let mediaID = expected.work.nextMediaID else { throw Persistence.IntegrityError.conflict }
        if let receipt = expected.work.receipt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let expiry = formatter.date(from: receipt.expiresAt), expiry > now else { throw Persistence.IntegrityError.conflict }
        }
        let work = try Work(stagedData: expected.work.stagedData, attempts: expected.work.attempts + [.init(id: attemptID, mediaID: mediaID, phase: .running, receipt: nil)])
        return try Claim(Persistence.transaction(proof.preparation.identity, container: container, isCurrent: isCurrent, save: save) { context in
            let current = try pair(proof, container, context)
            guard current.snapshot == expected else { throw Persistence.IntegrityError.conflict }
            return try write(work, current.job, container)
        })
    }
    static func validate(_ claim: Claim, proof: ObservationVideoPreparation.Verified, container: ModelContainer, isCurrent: () -> Bool) throws {
        guard claim.snapshot.containerID == ObjectIdentifier(container), claim.snapshot.work.attempts.last?.phase == .running else { throw Persistence.IntegrityError.conflict }
        guard try read(proof: proof, container: container, isCurrent: isCurrent) == claim.snapshot else { throw Persistence.IntegrityError.conflict }
    }
    static func hold(_ claim: Claim, proof: ObservationVideoPreparation.Verified, container: ModelContainer,
                     isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Snapshot {
        try finish(claim, receipt: nil, proof: proof, container: container, isCurrent: isCurrent, save: save)
    }
    static func settle(_ claim: Claim, receipt: ObservationVideoEvidenceReceipt, proof: ObservationVideoPreparation.Verified,
                       container: ModelContainer, isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Snapshot {
        try finish(claim, receipt: receipt, proof: proof, container: container, isCurrent: isCurrent, save: save)
    }
    private static func finish(_ claim: Claim, receipt: ObservationVideoEvidenceReceipt?, proof: ObservationVideoPreparation.Verified,
                               container: ModelContainer, isCurrent: () -> Bool, save: (ModelContext) throws -> Void) throws -> Snapshot {
        let original = claim.snapshot.work
        guard claim.snapshot.containerID == ObjectIdentifier(container), original.staged.reservation.preparation == proof.preparation,
              let last = original.attempts.last, last.phase == .running else { throw Persistence.IntegrityError.conflict }
        let prefix = Array(original.attempts.dropLast())
        let work = try Work(stagedData: original.stagedData, attempts: prefix + [.init(id: last.id, mediaID: last.mediaID,
            phase: receipt == nil ? .unknown : .observed, receipt: receipt)])
        let unknown = try Work(stagedData: original.stagedData, attempts: prefix + [.init(id: last.id, mediaID: last.mediaID, phase: .unknown, receipt: nil)])
        let metadata = String(decoding: try work.storedData(), as: UTF8.self)
        let unknownMetadata = String(decoding: try unknown.storedData(), as: UTF8.self)
        return try Persistence.transaction(proof.preparation.identity, container: container, isCurrent: isCurrent, save: save,
            settlingVideoUpload: receipt) { context in
                let current = try pair(proof, container, context)
                if current.snapshot.metadata == metadata { return current.snapshot }
                guard current.snapshot == claim.snapshot || (receipt != nil && current.snapshot.metadata == unknownMetadata) else { throw Persistence.IntegrityError.conflict }
                return try write(work, current.job, container)
            }
    }
    private static func pair(_ proof: ObservationVideoPreparation.Verified, _ container: ModelContainer, _ context: ModelContext) throws -> (snapshot: Snapshot, job: OfflineJobRecord) {
        try proof.validate(context: context)
        try Persistence.requireNoResultCollision(proof.preparation.identity, context: context)
        guard let (row, job) = try Persistence.pair(proof.preparation.identity, context: context), let text = job.metadataJSON,
              text.utf8.count <= Work.maximumBytes else { throw Persistence.IntegrityError.unavailable }
        try ObservationVideoPreparationStore.validateRow(proof.preparation, row: row, job: job)
        let work = try Work.decode(Data(text.utf8))
        guard work.staged.reservation.preparation == proof.preparation else { throw Persistence.IntegrityError.conflict }
        return (.init(work: work, metadata: text, containerID: ObjectIdentifier(container)), job)
    }
    private static func write(_ work: Work, _ job: OfflineJobRecord, _ container: ModelContainer) throws -> Snapshot {
        let metadata = String(decoding: try work.storedData(), as: UTF8.self)
        job.metadataJSON = metadata
        return .init(work: work, metadata: metadata, containerID: ObjectIdentifier(container))
    }
}
