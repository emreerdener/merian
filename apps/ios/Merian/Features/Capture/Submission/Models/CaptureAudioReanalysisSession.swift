import Foundation
import SwiftData

/// Prepared Capture boundary only; no live route, scheduler, legacy admission or funding fallback.
@MainActor
final class CaptureAudioReanalysisSession {
    typealias Start = @MainActor (ObservationAudioExecutionStore.Snapshot, ObservationAudioPreparation.Verified) -> ObservationAudioExecutionOwner.Admission
    let source: ObservationReanalysisSource
    let generation: UUID
    private let container: ModelContainer
    private(set) var plan: CaptureAudioReanalysisPlan?
    private var verified: CaptureAudioReanalysisPlan.Verified?
    private var submitting = false

    init(source: ObservationReanalysisSource, generation: UUID, container: ModelContainer) {
        self.source = source; self.generation = generation; self.container = container
    }

    /// Call at the actual tap, before scheduling asynchronous submission.
    @discardableResult
    func freeze(_ choices: [CaptureAudioReanalysisPlan.Choice], generation: UUID) throws -> CaptureAudioReanalysisPlan {
        guard generation == self.generation else { throw ObservationHistoryError.accountChanged }
        if let plan {
            guard plan.choices == choices else { throw ObservationHistoryError.resultConflict }
            return plan
        }
        let plan = try CaptureAudioReanalysisPlan(source: source, choices: choices)
        self.plan = plan
        return plan
    }

    /// The injected start closure owns common account scope; it must not capture presentation currentness.
    func submit(generation: UUID, producer: ObservationAudioPreparationProducer, binding: ObservationAudioSubmissionBinding,
                isCurrentAccount: @escaping @MainActor @Sendable () -> Bool,
                isCurrentPresentation: @escaping @MainActor @Sendable () -> Bool,
                save: @escaping @MainActor @Sendable (ModelContext) throws -> Void = { try $0.save() },
                start: Start) async throws -> ObservationAudioExecutionOwner.Admission {
        guard !submitting, producer.ownership === binding.ownership, let plan else { throw ObservationHistoryError.unavailable }
        let current: @MainActor @Sendable () -> Bool = { isCurrentAccount() && isCurrentPresentation() }
        func validate() throws {
            try Task.checkCancellation()
            guard generation == self.generation, current() else { throw ObservationHistoryError.accountChanged }
            try source.validate(container: container)
        }
        try validate()
        submitting = true
        defer { submitting = false }
        let input = try await verifiedInput(plan, validate: validate)
        let snapshot: ObservationAudioExecutionStore.Snapshot
        switch try ObservationAudioExecutionStore.admissionState(input.proof, container: container, isCurrent: isCurrentAccount) {
        case let .bound(saved): snapshot = saved
        case .unprepared, .preparation:
            let phase = try await producer.prepare(input.proof.preparation, source: source, bytes: input.bytes,
                container: container, isCurrent: isCurrentAccount)
            try validate()
            guard phase == .admissionPending else { throw ObservationHistoryError.resultConflict }
            snapshot = try await binding.bind(input.proof, container: container, isCurrent: isCurrentAccount, save: save)
        }
        try validate()
        guard try ObservationAudioExecutionStore.read(input.proof, container: container, isCurrent: isCurrentAccount) == snapshot else {
            throw ObservationHistoryError.resultConflict
        }
        return start(snapshot, input.proof)
    }
    /// Presentation outcome only; neither retained owner's admission is a provider permission.
    enum SourceAdmission: Equatable {
        case started, coalesced, unavailable
        init(_ value: ObservationAudioExecutionOwner.Admission) {
            switch value {
            case .started: self = .started
            case .coalesced: self = .coalesced
            case .unavailable: self = .unavailable
            }
        }
        init(_ value: ObservationSourceReservationOwner.Admission) {
            switch value {
            case .started: self = .started
            case .coalesced: self = .coalesced
            case .unavailable: self = .unavailable
            }
        }
    }

    func submitSource(generation: UUID, preparation: ObservationAudioSourcePreparation,
                      isCurrentAccount: @escaping @MainActor @Sendable () -> Bool,
                      isCurrentPresentation: @escaping @MainActor @Sendable () -> Bool,
                      save: @escaping @MainActor @Sendable (ModelContext) throws -> Void = { try $0.save() },
                      start: @MainActor (ObservationAudioSourcePreparation.Ready, ObservationAudioPreparation.Verified) -> SourceAdmission) async throws -> SourceAdmission {
        guard !submitting, let plan else { throw ObservationHistoryError.unavailable }
        func validate() throws {
            try Task.checkCancellation()
            guard generation == self.generation, isCurrentAccount(), isCurrentPresentation() else { throw ObservationHistoryError.accountChanged }
            try source.validate(container: container)
        }
        try validate()
        submitting = true
        defer { submitting = false }
        let input = try await verifiedInput(plan, validate: validate)
        let saved = try await preparation.prepare(input.proof, source: source, bytes: input.bytes,
            container: container, isCurrent: isCurrentAccount, save: save)
        try validate()
        return start(saved, input.proof)
    }

    private func verifiedInput(_ plan: CaptureAudioReanalysisPlan, validate: () throws -> Void) async throws -> CaptureAudioReanalysisPlan.Verified {
        if let verified { return verified }
        let input = try await DetachedWork.value(category: .inferenceRequestPreparation) { try plan.verify() }
        try validate()
        verified = input
        return input
    }

}
