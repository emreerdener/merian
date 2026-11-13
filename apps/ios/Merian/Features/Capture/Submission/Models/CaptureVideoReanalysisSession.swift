import Foundation
import SwiftData

/// One explicit current attachment and ordered text, retained across presentation dismissal.
@MainActor
final class CaptureVideoReanalysisSession {
    struct Plan: Equatable {
        let analysisID: UUID
        let choice: ObservationReanalysisLocalVideoInput.Choice
        let descriptions: [String]
    }
    let source: ObservationReanalysisSource
    let generation: UUID
    private let container: ModelContainer
    private(set) var plan: Plan?
    private var input: ObservationReanalysisLocalVideoInput?
    private var verified: ObservationVideoPreparation.Verified?
    private var submitting = false
    private var invalidated = false

    init(source: ObservationReanalysisSource, generation: UUID, container: ModelContainer) {
        self.source = source; self.generation = generation; self.container = container
    }

    /// Final tap fixes the child ID and choice/text before scheduling asynchronous copying.
    @discardableResult
    func freeze(_ choice: ObservationReanalysisLocalVideoInput.Choice, descriptions: [String], generation: UUID) throws -> Plan {
        guard !invalidated, generation == self.generation, choice.source == source else { throw ObservationHistoryError.accountChanged }
        if let plan {
            guard plan.choice == choice, plan.descriptions == descriptions else { throw ObservationHistoryError.resultConflict }
            return plan
        }
        try source.validate(container: container)
        try ObservationVideoManifest.validateDescriptions(descriptions)
        guard !descriptions.contains(where: { $0.unicodeScalars.contains(where: { $0.value == 0 }) }) else { throw MerianError.invalidResponse }
        let plan = Plan(analysisID: UUID(), choice: choice, descriptions: descriptions)
        self.plan = plan
        return plan
    }

    func submit(generation: UUID, files: FileIOActor, temporaryDirectory: URL, startup: NativeReleaseStartupAdmission,
                borrowing: SharedMediaNativeOriginalDrain.LocalBorrow? = nil,
                producer: ObservationVideoPreparationProducer,
                isCurrentAccount: @escaping @MainActor @Sendable () -> Bool,
                isCurrentPresentation: @escaping @MainActor @Sendable () -> Bool,
                start: @MainActor (ObservationVideoResumeSubmission.Ready) -> CaptureVideoResumeAccess.Admission) async throws -> CaptureVideoResumeAccess.Admission {
        guard !submitting, !invalidated, let plan else { throw ObservationHistoryError.unavailable }
        func validate() throws {
            try Task.checkCancellation()
            guard !invalidated, generation == self.generation, isCurrentAccount(), isCurrentPresentation() else {
                throw ObservationHistoryError.accountChanged
            }
            try source.validate(container: container)
        }
        try validate()
        submitting = true
        defer { submitting = false }
        if verified == nil {
            if input == nil {
                _ = try await ObservationReanalysisLocalVideoInput.freeze(plan.choice, descriptions: plan.descriptions,
                    container: container, files: files, account: producer.account, startup: startup, borrowing: borrowing, store: producer.files,
                    ownership: producer.ownership, analysisID: plan.analysisID,
                    owning: { input in self.input = input }, isCurrent: { isCurrentAccount() && isCurrentPresentation() && !self.invalidated })
            }
            try validate()
            guard let input else { throw ObservationHistoryError.unavailable }
            let proof = try await input.prepare(container: container, account: producer.account, producer: producer,
                temporaryDirectory: temporaryDirectory, isCurrent: isCurrentAccount)
            // Cache the exact prepared child before any queue phase can replace preparation metadata.
            verified = proof
            if await input.discardCopiedInput() { self.input = nil }
        }
        try validate()
        guard let verified, verified.preparation.identity.analysisID == plan.analysisID else { throw ObservationHistoryError.resultConflict }
        let service = ObservationVideoResumeSubmission(producer: producer)
        guard let ready = try await service.resume(verified.preparation.identity, container: container, isCurrent: isCurrentAccount) else { return .unavailable }
        try validate()
        try ObservationVideoResumeSubmission.validate(ready, container: container, isCurrent: isCurrentAccount)
        return start(ready)
    }

    var isRuntimeQuiescent: Bool { !submitting && input?.isRuntimeQuiescent != false }

    /// Host cancels and awaits its active task before calling this. False retains cleanup responsibility.
    func shutdown() async -> Bool {
        invalidated = true
        guard !submitting else { return false }
        guard let input else { return true }
        guard await input.discardCopiedInput() else { return false }
        self.input = nil
        return true
    }
}
