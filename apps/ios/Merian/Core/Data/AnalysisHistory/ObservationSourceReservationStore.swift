import Foundation
import SwiftData

/// Exact local photo handoff. No discovery, network, timers or execution admission.
@MainActor
enum ObservationSourceReservationStore {
    typealias Work = ObservationSourceReservationWork
    typealias Proof = ObservationReanalysisPreparationIntent.Verified
    private typealias Persistence = ObservationReanalysisPersistence
    enum Admission { case initial, explicitRecovery }
    struct Snapshot: Equatable, Sendable {
        let work: Work
        let metadata: String
        let containerID: ObjectIdentifier
        var identity: OfflineQueueWork.Reanalysis { work.identity }
    }
    struct Claim: Sendable {
        let snapshot: Snapshot
        fileprivate init(_ snapshot: Snapshot) { self.snapshot = snapshot }
    }

    /// Consumes only the exact running, verified ready-submission claim. Replay never rearms work.
    static func stage(_ admission: ObservationReanalysisAdmissionStore.Claim, request: ObservationSourceReservationRequest,
                      proof: Proof, container: ModelContainer, isCurrent: () -> Bool,
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Snapshot {
        guard admission.snapshot.work.phase == .admissionPending,
              admission.snapshot.work.preparation == proof.pending else { throw Persistence.IntegrityError.conflict }
        let work = try Work(preparation: proof.pending, request: request)
        return try Persistence.transaction(work.identity, container: container, isCurrent: isCurrent, save: save) { context in
            try proof.validate(context: context)
            if let (_, job) = try Persistence.pair(work.identity, context: context), let metadata = job.metadataJSON,
               (try? Work.decode(Data(metadata.utf8))) != nil {
                let saved = try pair(work.identity, container: container, context: context).snapshot
                guard saved.work.preparation == work.preparation, saved.work.request == request else { throw Persistence.IntegrityError.conflict }
                return saved
            }
            let original = try ObservationReanalysisAdmissionStore.matching(admission, proof: proof, context: context)
            return try write(work, job: original.job, container: container)
        }
    }

    static func read(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer, isCurrent: () -> Bool) throws -> Snapshot {
        try Persistence.transaction(identity, container: container, isCurrent: isCurrent, save: { try $0.save() }) { context in
            try pair(identity, container: container, context: context).snapshot
        }
    }

    /// Explicit recovery may replace an interrupted claim only after its retained owner has drained.
    static func claim(_ expected: Snapshot, admission: Admission, proof: Proof, container: ModelContainer,
                      isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Claim {
        switch admission {
        case .initial: guard expected.work.state == .staged else { throw Persistence.IntegrityError.conflict }
        case .explicitRecovery:
            guard [.running, .unknown, .observed].contains(expected.work.state), expected.work.reply?.state != .reserved else {
                throw Persistence.IntegrityError.conflict
            }
        }
        let work = try Work(preparation: expected.work.preparation, request: expected.work.request,
            state: .running, generation: expected.work.generation + 1)
        return try Claim(change(expected, to: work, proof: proof, container: container, isCurrent: isCurrent, save: save))
    }

    static func validate(_ claim: Claim, proof: Proof, container: ModelContainer, isCurrent: () -> Bool) throws {
        _ = try Persistence.transaction(claim.snapshot.identity, container: container, isCurrent: isCurrent, save: { try $0.save() }) { context in
            try matching(claim.snapshot, proof: proof, container: container, context: context)
        }
    }

    static func settle(_ claim: Claim, reply: ObservationSourceReservationReply, proof: Proof,
                       container: ModelContainer, isCurrent: () -> Bool,
                       save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Snapshot {
        guard claim.snapshot.work.state == .running else { throw Persistence.IntegrityError.conflict }
        let work = try Work(preparation: claim.snapshot.work.preparation, request: claim.snapshot.work.request,
            state: .observed, generation: claim.snapshot.work.generation, reply: reply)
        return try change(claim.snapshot, to: work, proof: proof, container: container, isCurrent: isCurrent,
            settlingSource: reply, save: save)
    }

    static func hold(_ claim: Claim, proof: Proof, container: ModelContainer, isCurrent: () -> Bool,
                     conflict: ObservationSourceReservationConflict? = nil,
                     save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Snapshot {
        guard claim.snapshot.work.state == .running else { throw Persistence.IntegrityError.conflict }
        if let conflict {
            guard conflict.ownerID == claim.snapshot.identity.ownerID, conflict.request == claim.snapshot.work.request else {
                throw Persistence.IntegrityError.conflict
            }
        }
        let work = try Work(preparation: claim.snapshot.work.preparation, request: claim.snapshot.work.request,
            state: conflict == nil ? .unknown : .conflict, generation: claim.snapshot.work.generation)
        return try change(claim.snapshot, to: work, proof: proof, container: container, isCurrent: isCurrent, save: save)
    }

    private static func change(_ expected: Snapshot, to work: Work, proof: Proof, container: ModelContainer,
                               isCurrent: () -> Bool, settlingSource: ObservationSourceReservationReply? = nil,
                               save: (ModelContext) throws -> Void) throws -> Snapshot {
        try Persistence.transaction(expected.identity, container: container, isCurrent: isCurrent, save: save,
            settlingSource: settlingSource) { context in
            let job = try matching(expected, proof: proof, container: container, context: context)
            return try write(work, job: job, container: container)
        }
    }

    private static func matching(_ expected: Snapshot, proof: Proof, container: ModelContainer, context: ModelContext) throws -> OfflineJobRecord {
        guard expected.containerID == ObjectIdentifier(container), proof.pending == expected.work.preparation else {
            throw Persistence.IntegrityError.conflict
        }
        try proof.validate(context: context)
        let saved = try pair(expected.identity, container: container, context: context)
        guard saved.snapshot == expected else { throw Persistence.IntegrityError.conflict }
        return saved.job
    }

    private static func write(_ work: Work, job: OfflineJobRecord, container: ModelContainer) throws -> Snapshot {
        guard let metadata = String(bytes: try work.storedData(), encoding: .utf8) else { throw Persistence.IntegrityError.conflict }
        let persisted = try Work.decode(Data(metadata.utf8))
        job.metadataJSON = metadata
        return .init(work: persisted, metadata: metadata, containerID: ObjectIdentifier(container))
    }

    private static func pair(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
                             context: ModelContext) throws -> (snapshot: Snapshot, job: OfflineJobRecord) {
        try Persistence.requireNoResultCollision(identity, context: context)
        guard let (row, job) = try Persistence.pair(identity, context: context), let metadata = job.metadataJSON else {
            throw Persistence.IntegrityError.unavailable
        }
        let work = try Work.decode(Data(metadata.utf8))
        try ObservationReanalysisAdmissionStore.validatePristinePair(identity, preparation: work.preparation, row: row, job: job)
        return (.init(work: work, metadata: metadata, containerID: ObjectIdentifier(container)), job)
    }
}
