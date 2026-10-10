import Foundation
import SwiftData

/// Private reservation evidence. Decoding is never upload, release or execution authority.
struct ObservationVideoSourceReservationWork: Equatable, Sendable {
    // Both independently bounded blobs may expand in base64; include fixed envelope overhead.
    static let maximumStagedBytes = ((ObservationVideoPreparation.maximumStoredBytes + 2) / 3) * 4
        + ((ObservationVideoSourceReservationRequest.maximumBytes + 2) / 3) * 4 + 256
    static let maximumBytes = ((maximumStagedBytes + 2) / 3) * 4
        + ((ObservationVideoSourceReservationReply.maximumBytes + 2) / 3) * 4 + 512
    static let kind = "video_source_reservation"
    enum Phase: String, Sendable { case staged, running, unknown, observed, conflict }
    let preparation: ObservationVideoPreparation
    let request: ObservationVideoSourceReservationRequest
    let phase: Phase
    let attemptID: UUID?
    let reply: ObservationVideoSourceReservationReply?
    let stagedData: Data

    init(preparation: ObservationVideoPreparation, request: ObservationVideoSourceReservationRequest,
         phase: Phase = .staged, attemptID: UUID? = nil, reply: ObservationVideoSourceReservationReply? = nil,
         stagedData: Data? = nil) throws {
        guard request.input == preparation.request.body,
              try ObservationVideoSourceReservationRequest(video: preparation.request) == request else {
            throw MerianError.invalidResponse
        }
        guard (phase == .staged) == (attemptID == nil) else { throw MerianError.invalidResponse }
        if phase == .observed {
            guard let reply, reply.identity == request.identity, reply.ownerID == preparation.identity.ownerID else {
                throw MerianError.invalidResponse
            }
        } else { guard reply == nil else { throw MerianError.invalidResponse } }
        if let stagedData {
            let saved = try Self.decodeStaged(stagedData)
            guard saved.preparation == preparation, saved.request == request else { throw MerianError.invalidResponse }
            self.stagedData = stagedData
        } else {
            self.stagedData = try Self.encodeStaged(preparation: preparation, request: request)
        }
        self.phase = phase; self.attemptID = attemptID; self.reply = reply
        self.preparation = preparation; self.request = request
    }

    func storedData() throws -> Data {
        guard let attemptID else { return stagedData }
        let row: [String: Any] = ["version": 2, "kind": Self.kind, "phase": phase.rawValue,
            "staged_base64": stagedData.base64EncodedString(), "attempt_id": attemptID.uuidString.lowercased(),
            "reply_base64": reply.map { $0.data.base64EncodedString() as Any } ?? NSNull()]
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= Self.maximumBytes else { throw MerianError.invalidResponse }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= maximumBytes,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MerianError.invalidResponse }
        if try ObservationHistoryPage.integer(row["version"]) == 1 {
            let saved = try decodeStaged(data)
            return try .init(preparation: saved.preparation, request: saved.request, stagedData: data)
        }
        guard try ObservationHistoryPage.integer(row["version"]) == 2,
              Set(row.keys) == ["version", "kind", "phase", "staged_base64", "attempt_id", "reply_base64"],
              row["kind"] as? String == kind, let raw = row["phase"] as? String,
              let phase = Phase(rawValue: raw), phase != .staged else { throw MerianError.invalidResponse }
        let attemptID = try ObservationHistoryPage.uuid(row["attempt_id"])
        guard row["attempt_id"] as? String == attemptID.uuidString.lowercased() else { throw MerianError.invalidResponse }
        let stagedData = try bytes(row["staged_base64"], maximum: maximumStagedBytes)
        let saved = try decodeStaged(stagedData)
        let reply: ObservationVideoSourceReservationReply?
        if row["reply_base64"] is NSNull { reply = nil } else {
            reply = try .init(data: bytes(row["reply_base64"], maximum: ObservationVideoSourceReservationReply.maximumBytes),
                identity: saved.request.identity, ownerID: saved.preparation.identity.ownerID)
        }
        return try .init(preparation: saved.preparation, request: saved.request, phase: phase, attemptID: attemptID,
                         reply: reply, stagedData: stagedData)
    }

    private static func encodeStaged(preparation: ObservationVideoPreparation, request: ObservationVideoSourceReservationRequest) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "kind": kind, "phase": "staged",
            "preparation_base64": try preparation.storedData(phase: .ready).base64EncodedString(),
            "candidate_base64": request.body.base64EncodedString()], options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= maximumStagedBytes else { throw MerianError.invalidResponse }
        return data
    }

    private static func decodeStaged(_ data: Data) throws -> (preparation: ObservationVideoPreparation, request: ObservationVideoSourceReservationRequest) {
        guard !data.isEmpty, data.count <= maximumStagedBytes else { throw MerianError.invalidResponse }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data), keys: [
            "version", "kind", "phase", "preparation_base64", "candidate_base64"
        ])
        guard try ObservationHistoryPage.integer(row["version"]) == 1,
              row["kind"] as? String == kind, row["phase"] as? String == "staged" else { throw MerianError.invalidResponse }
        let saved = try ObservationVideoPreparation.decode(bytes(row["preparation_base64"], maximum: ObservationVideoPreparation.maximumStoredBytes))
        guard saved.phase == .ready else { throw MerianError.invalidResponse }
        let request = try ObservationVideoSourceReservationRequest(savedInput: saved.preparation.request.body,
            savedBody: bytes(row["candidate_base64"], maximum: ObservationVideoSourceReservationRequest.maximumBytes))
        return (saved.preparation, request)
    }

    private static func bytes(_ value: Any?, maximum: Int) throws -> Data {
        guard let text = value as? String, text.utf8.count <= ((maximum + 2) / 3) * 4,
              let bytes = Data(base64Encoded: text), bytes.count <= maximum,
              bytes.base64EncodedString() == text else { throw MerianError.invalidResponse }
        return bytes
    }
}

/// Exact local claim and settlement. No discovery, network, retry or replacement candidate.
@MainActor
enum ObservationVideoSourceReservationStore {
    private typealias Persistence = ObservationReanalysisPersistence
    private typealias Work = ObservationVideoSourceReservationWork
    struct Claim: Sendable {
        let snapshot: Snapshot
        fileprivate init(_ snapshot: Snapshot) { self.snapshot = snapshot }
    }
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
                guard saved.preparation == work.preparation, saved.request == work.request else { throw Persistence.IntegrityError.conflict }
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
                try pair(proof: proof, container: container, context: context).snapshot
            }
    }

    /// Initial admission only. A lost claim save reply leaves durable running work held.
    static func claim(_ expected: Snapshot, proof: ObservationVideoPreparation.Verified, container: ModelContainer,
                      isCurrent: () -> Bool, attemptID: UUID = UUID(),
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Claim {
        guard expected.containerID == ObjectIdentifier(container), expected.work.phase == .staged else { throw Persistence.IntegrityError.conflict }
        let work = try Work(preparation: expected.work.preparation, request: expected.work.request, phase: .running, attemptID: attemptID, stagedData: expected.work.stagedData)
        return try Claim(Persistence.transaction(proof.preparation.identity, container: container, isCurrent: isCurrent, save: save) { context in
            let current = try pair(proof: proof, container: container, context: context)
            guard current.snapshot == expected else { throw Persistence.IntegrityError.conflict }
            return try write(work, job: current.job, container: container)
        })
    }

    /// Dispatch validation cannot accept unknown, settled, cancelled or superseded claims.
    static func validate(_ claim: Claim, proof: ObservationVideoPreparation.Verified, container: ModelContainer,
                         isCurrent: () -> Bool) throws {
        guard claim.snapshot.containerID == ObjectIdentifier(container) else { throw Persistence.IntegrityError.conflict }
        try Persistence.transaction(proof.preparation.identity, container: container, isCurrent: isCurrent,
            save: { _ in throw Persistence.IntegrityError.conflict }) { context in
                guard try pair(proof: proof, container: container, context: context).snapshot == claim.snapshot else {
                    throw Persistence.IntegrityError.conflict
                }
            }
    }

    static func hold(_ claim: Claim, proof: ObservationVideoPreparation.Verified, container: ModelContainer,
                     isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Snapshot {
        try finish(claim, settlement: nil, proof: proof, container: container, isCurrent: isCurrent, save: save)
    }

    /// Known answers may survive dispatch cancellation, never changed account/source/claim scope.
    static func settle(_ claim: Claim, settlement: ObservationVideoReservationSettlement,
                       proof: ObservationVideoPreparation.Verified, container: ModelContainer, isCurrent: () -> Bool,
                       save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Snapshot {
        try finish(claim, settlement: settlement, proof: proof, container: container, isCurrent: isCurrent, save: save)
    }

    private static func finish(_ claim: Claim, settlement: ObservationVideoReservationSettlement?,
                               proof: ObservationVideoPreparation.Verified, container: ModelContainer,
                               isCurrent: () -> Bool, save: (ModelContext) throws -> Void) throws -> Snapshot {
        let original = claim.snapshot.work
        guard claim.snapshot.containerID == ObjectIdentifier(container), proof.preparation == original.preparation,
              original.phase == .running else { throw Persistence.IntegrityError.conflict }
        let phase: Work.Phase
        let reply: ObservationVideoSourceReservationReply?
        switch settlement {
        case let .reply(value): phase = .observed; reply = value
        case let .conflict(value):
            guard value.request == original.request, value.ownerID == original.preparation.identity.ownerID else { throw Persistence.IntegrityError.conflict }
            phase = .conflict; reply = nil
        case nil: phase = .unknown; reply = nil
        }
        let work = try Work(preparation: original.preparation, request: original.request, phase: phase, attemptID: original.attemptID, reply: reply, stagedData: original.stagedData)
        let unknown = try Work(preparation: original.preparation, request: original.request, phase: .unknown, attemptID: original.attemptID, stagedData: original.stagedData)
        let expectedMetadata = String(decoding: try work.storedData(), as: UTF8.self)
        let unknownMetadata = String(decoding: try unknown.storedData(), as: UTF8.self)
        return try Persistence.transaction(original.preparation.identity, container: container, isCurrent: isCurrent, save: save,
            settlingVideo: settlement) { context in
                let current = try pair(proof: proof, container: container, context: context)
                if current.snapshot.metadata == expectedMetadata { return current.snapshot }
                guard current.snapshot == claim.snapshot || (settlement != nil && current.snapshot.metadata == unknownMetadata) else {
                    throw Persistence.IntegrityError.conflict
                }
                return try write(work, job: current.job, container: container)
            }
    }

    private static func write(_ work: Work, job: OfflineJobRecord, container: ModelContainer) throws -> Snapshot {
        guard let text = String(data: try work.storedData(), encoding: .utf8) else { throw Persistence.IntegrityError.conflict }
        job.metadataJSON = text
        return .init(work: work, metadata: text, containerID: ObjectIdentifier(container))
    }

    private static func pair(proof: ObservationVideoPreparation.Verified, container: ModelContainer,
                             context: ModelContext) throws -> (snapshot: Snapshot, job: OfflineJobRecord) {
        try proof.validate(context: context)
        try Persistence.requireNoResultCollision(proof.preparation.identity, context: context)
        guard let (row, job) = try Persistence.pair(proof.preparation.identity, context: context),
              let text = job.metadataJSON else { throw Persistence.IntegrityError.unavailable }
        guard text.utf8.count <= Work.maximumBytes else { throw Persistence.IntegrityError.conflict }
        let work = try Work.decode(Data(text.utf8))
        guard work.preparation == proof.preparation else { throw Persistence.IntegrityError.conflict }
        try ObservationVideoPreparationStore.validateRow(work.preparation, row: row, job: job)
        return (.init(work: work, metadata: text, containerID: ObjectIdentifier(container)), job)
    }
}

/// Typed known reservation evidence only; never an execution or cleanup receipt.
enum ObservationVideoReservationSettlement: Sendable {
    case reply(ObservationVideoSourceReservationReply)
    case conflict(ObservationVideoSourceReservationConflict)

    func validate(_ identity: OfflineQueueWork.Reanalysis) throws {
        let ownerID: UUID, scope: ObservationVideoSourceIdentity
        switch self {
        case let .reply(reply): ownerID = reply.ownerID; scope = reply.identity
        case let .conflict(conflict): ownerID = conflict.ownerID; scope = conflict.request.identity
        }
        guard ownerID == identity.ownerID, scope.observationID == identity.observationID,
              scope.sourceAnalysisID == identity.sourceAnalysisID, scope.analysisID == identity.analysisID else {
            throw ObservationReanalysisPersistence.IntegrityError.conflict
        }
    }
}
