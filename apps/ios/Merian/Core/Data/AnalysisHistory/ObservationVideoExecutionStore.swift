import Foundation
import SwiftData

/// Existing held child only. No scheduler, HTTP, result insertion or file cleanup.
@MainActor
enum ObservationVideoExecutionStore {
    private typealias Persistence = ObservationReanalysisPersistence
    typealias Work = ObservationVideoExecutionWork
    struct Snapshot: Equatable, Sendable {
        let work: Work
        let metadata: String
        let containerID: ObjectIdentifier
    }
    struct Claim: Sendable {
        let snapshot: Snapshot
        fileprivate init(_ snapshot: Snapshot) { self.snapshot = snapshot }
    }
    /// Constructed only after consumed=true is durably saved; never reconstructed by read.
    struct DispatchPermit: Sendable {
        let snapshot: Snapshot
        fileprivate init(_ snapshot: Snapshot) { self.snapshot = snapshot }
    }

    static func stage(_ uploaded: ObservationVideoUploadLifecycleStore.Snapshot,
                      proof: ObservationVideoPreparation.Verified, authorization: IdentificationDispatchAuthorization,
                      container: ModelContainer, isCurrent: () -> Bool, now: Date = Date(),
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Snapshot {
        guard uploaded.containerID == ObjectIdentifier(container), uploaded.work.staged.reservation.preparation == proof.preparation else {
            throw Persistence.IntegrityError.conflict
        }
        let work = try Work(uploadData: Data(uploaded.metadata.utf8))
        guard work.upload == uploaded.work else { throw Persistence.IntegrityError.conflict }
        func resolve(_ context: ModelContext) throws -> (OfflineJobRecord, Snapshot?) {
            let (job, text) = try pair(proof, context)
            if let saved = try? Work.decode(Data(text.utf8)) {
                guard saved.uploadData == work.uploadData else { throw Persistence.IntegrityError.conflict }
                return (job, .init(work: saved, metadata: text, containerID: ObjectIdentifier(container)))
            }
            guard text == uploaded.metadata else { throw Persistence.IntegrityError.conflict }
            return (job, nil)
        }
        let prior = try Persistence.transaction(proof.preparation.identity, container: container, isCurrent: isCurrent,
            save: { _ in throw Persistence.IntegrityError.conflict }) { try resolve($0).1 }
        if let prior { return prior }
        // Consent may inspect persistence. Validate outside the transaction lock.
        guard authorization.recipient == .gemini else { throw MerianError.aiConsentRequired }
        try authorization.validate()
        return try Persistence.transaction(proof.preparation.identity, container: container, isCurrent: isCurrent, save: save) { context in
            let (job, prior) = try resolve(context)
            if let prior { return prior }
            try work.requireUnexpired(at: now)
            return try write(work, job, container)
        }
    }

    static func read(proof: ObservationVideoPreparation.Verified, container: ModelContainer, isCurrent: () -> Bool) throws -> Snapshot {
        try Persistence.transaction(proof.preparation.identity, container: container, isCurrent: isCurrent,
            save: { _ in throw Persistence.IntegrityError.conflict }) { context in
                try snapshot(proof, container, context).0
            }
    }

    static func claim(_ expected: Snapshot, proof: ObservationVideoPreparation.Verified, container: ModelContainer,
                      isCurrent: () -> Bool, attemptID: UUID = UUID(), now: Date = Date(),
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Claim {
        guard expected.work.phase == .idle, !expected.work.consumed else { throw Persistence.IntegrityError.conflict }
        return try Claim(change(expected, proof, container, isCurrent, save) { work in
            try work.requireUnexpired(at: now)
            return try Work(uploadData: work.uploadData, phase: .running, attemptID: attemptID)
        })
    }

    static func consume(_ claim: Claim, proof: ObservationVideoPreparation.Verified,
                        authorization: IdentificationDispatchAuthorization, container: ModelContainer,
                        isCurrent: () -> Bool, now: Date = Date(),
                        save: (ModelContext) throws -> Void = { try $0.save() }) throws -> DispatchPermit {
        guard claim.snapshot.work.phase == .running, !claim.snapshot.work.consumed,
              authorization.recipient == .gemini else { throw Persistence.IntegrityError.conflict }
        try authorization.validate()
        return try DispatchPermit(change(claim.snapshot, proof, container, isCurrent, save) { work in
            try work.requireUnexpired(at: now)
            return try Work(uploadData: work.uploadData, phase: .running, attemptID: work.attemptID, consumed: true)
        })
    }

    static func validateDispatch(_ permit: DispatchPermit, proof: ObservationVideoPreparation.Verified,
                                 container: ModelContainer, isCurrent: () -> Bool, now: Date = Date()) throws {
        guard permit.snapshot.containerID == ObjectIdentifier(container), permit.snapshot.work.phase == .running,
              permit.snapshot.work.consumed,
              try read(proof: proof, container: container, isCurrent: isCurrent) == permit.snapshot else {
            throw Persistence.IntegrityError.conflict
        }
        try permit.snapshot.work.requireUnexpired(at: now)
    }

    /// Failed/uncertain work is retained verbatim. No reset or second claim is exposed.
    static func hold(_ expected: Snapshot, proof: ObservationVideoPreparation.Verified, container: ModelContainer,
                     isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Snapshot {
        guard expected.work.phase == .running else { throw Persistence.IntegrityError.conflict }
        return try change(expected, proof, container, isCurrent, save) { work in
            try Work(uploadData: work.uploadData, phase: .held, attemptID: work.attemptID, consumed: work.consumed)
        }
    }

    private static func change(_ expected: Snapshot, _ proof: ObservationVideoPreparation.Verified, _ container: ModelContainer,
                               _ isCurrent: () -> Bool, _ save: (ModelContext) throws -> Void,
                               transform: (Work) throws -> Work) throws -> Snapshot {
        guard expected.containerID == ObjectIdentifier(container) else { throw Persistence.IntegrityError.conflict }
        return try Persistence.transaction(proof.preparation.identity, container: container, isCurrent: isCurrent, save: save) { context in
            let (saved, job) = try snapshot(proof, container, context)
            guard saved == expected else { throw Persistence.IntegrityError.conflict }
            return try write(transform(saved.work), job, container)
        }
    }
    private static func snapshot(_ proof: ObservationVideoPreparation.Verified, _ container: ModelContainer,
                                 _ context: ModelContext) throws -> (Snapshot, OfflineJobRecord) {
        let (job, text) = try pair(proof, context)
        let work = try Work.decode(Data(text.utf8))
        guard work.preparation == proof.preparation else { throw Persistence.IntegrityError.conflict }
        return (.init(work: work, metadata: text, containerID: ObjectIdentifier(container)), job)
    }
    private static func pair(_ proof: ObservationVideoPreparation.Verified, _ context: ModelContext) throws -> (OfflineJobRecord, String) {
        try proof.validate(context: context)
        try Persistence.requireNoResultCollision(proof.preparation.identity, context: context)
        guard let (row, job) = try Persistence.pair(proof.preparation.identity, context: context), let text = job.metadataJSON,
              text.utf8.count <= Work.maximumBytes else { throw Persistence.IntegrityError.unavailable }
        try ObservationVideoPreparationStore.validateRow(proof.preparation, row: row, job: job)
        return (job, text)
    }
    private static func write(_ work: Work, _ job: OfflineJobRecord, _ container: ModelContainer) throws -> Snapshot {
        let metadata = String(decoding: try work.storedData(), as: UTF8.self)
        job.metadataJSON = metadata
        return .init(work: work, metadata: metadata, containerID: ObjectIdentifier(container))
    }
}
