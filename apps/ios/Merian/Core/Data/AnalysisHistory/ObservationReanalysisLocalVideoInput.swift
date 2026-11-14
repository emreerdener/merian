import CryptoKit
import Foundation
import SwiftData

/// Explicit current attachment choice, never historical original-media evidence.
/// The existing source, FileIO and preparation owners retain their authority.
@MainActor
final class ObservationReanalysisLocalVideoInput {
    struct Choice: Equatable, Sendable {
        let source: ObservationReanalysisSource
        let mediaIndex: Int
        let filename: String
        fileprivate let capturedBytes: Data

        @MainActor fileprivate func validate(container: ModelContainer) throws {
            try ConfirmedSpeciesReviewPersistence.transaction { try validate(context: ModelContext(container)) }
        }

        @MainActor fileprivate func validate(context: ModelContext) throws {
            try source.validate(context: context)
            let scan = try ObservationHistorySyncService.enrolledScan(source.observationID.uuidString, context: context)
            guard scan.analysisOwnerAccountID == source.ownerID.uuidString.lowercased(),
                  try SharedMediaConsumerAuthority.classify(raw: scan.mediaAuthorityRaw,
                    consumerID: scan.sharedMediaConsumerID, record: .scan) == .legacy,
                  scan.capturedMediaJSON.map({ Data($0.utf8) }) == capturedBytes else {
                throw ObservationHistoryError.unavailable
            }
        }
    }

    let source: ObservationReanalysisSource
    let analysisID: UUID
    let descriptions: [String]
    private let choice: Choice
    private var copied: ObservationReanalysisFileStore.InputToken?
    private let container: ModelContainer
    private let startup: NativeReleaseStartupAdmission
    private let borrowing: SharedMediaNativeOriginalDrain.LocalBorrow?
    private let store: ObservationReanalysisFileStore
    private let ownership: ObservationReanalysisPreparationOwner
    private let planDigest: String
    private var fence: SharedMediaStoreReadFence?
    private var copyAttempted = false
    private let files: FileIOActor
    private var busy = false
    private var invalidated = false
    private var copiedInputReleased = false
    private var copyValidated = false
    #if DEBUG
    /// Observation-only suspension seam; it cannot bypass any live validation.
    var inputPhaseCheckpoint: (@Sendable (ObservationVideoCohortPhase) async throws -> Void)?
    #endif
    private var retainedCohort: ObservationVideoCohort?
    private(set) var preparation: ObservationVideoPreparation?

    private init(choice: Choice, analysisID: UUID, descriptions: [String], files: FileIOActor,
                 container: ModelContainer, startup: NativeReleaseStartupAdmission,
                 borrowing: SharedMediaNativeOriginalDrain.LocalBorrow?,
                 store: ObservationReanalysisFileStore, ownership: ObservationReanalysisPreparationOwner) throws {
        self.choice = choice
        source = choice.source; self.analysisID = analysisID; self.descriptions = descriptions
        self.files = files; self.container = container; self.startup = startup
        self.store = store; self.ownership = ownership; self.borrowing = borrowing
        // Hash exact byte encodings, including ordered text, without normalizing Unicode.
        let plan: [String: Any] = ["version": 1, "owner": source.ownerID.uuidString.lowercased(),
            "parent": source.observationID.uuidString.lowercased(), "source": source.analysisID.uuidString.lowercased(),
            "child": analysisID.uuidString.lowercased(), "snapshot": source.snapshot.base64EncodedString(),
            "captured": choice.capturedBytes.base64EncodedString(), "index": choice.mediaIndex,
            "filename": choice.filename, "descriptions": descriptions.map { Data($0.utf8).base64EncodedString() }]
        planDigest = SHA256.hash(data: try JSONSerialization.data(withJSONObject: plan, options: [.sortedKeys]))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Discovery does not select anything or grant access. No absolute/remote,
    /// private-store or current-selection fallback is interpreted as local input.
    static func choices(source: ObservationReanalysisSource, container: ModelContainer) throws -> [Choice] {
        try source.validate(container: container)
        let scan = try ObservationHistorySyncService.enrolledScan(source.observationID.uuidString,
            context: ModelContext(container))
        guard scan.analysisOwnerAccountID == source.ownerID.uuidString.lowercased(),
              try SharedMediaConsumerAuthority.classify(raw: scan.mediaAuthorityRaw,
                consumerID: scan.sharedMediaConsumerID, record: .scan) == .legacy,
              let raw = scan.capturedMediaJSON, raw.utf8.count <= 1_048_576 else { return [] }
        let bytes = Data(raw.utf8)
        return CapturedMediaSnapshot(jsonString: raw).items.enumerated().compactMap { index, item in
            guard case let .video(value) = item, value.video.storage == .documents,
                  !value.video.path.isEmpty, !value.video.path.contains("/"), !value.video.path.contains("\0") else { return nil }
            return Choice(source: source, mediaIndex: index, filename: value.video.path, capturedBytes: bytes)
        }
    }

    /// Retain responsibility before bootstrap, reservation or any copy can run.
    /// A failed attempt can only recover the exact copied receipt; it never recopies.
    static func freeze(_ choice: Choice, descriptions: [String], container: ModelContainer,
                       files: FileIOActor, account: ObservationHistoryCloudClient,
                       startup: NativeReleaseStartupAdmission, borrowing: SharedMediaNativeOriginalDrain.LocalBorrow? = nil,
                       store: ObservationReanalysisFileStore,
                       ownership: ObservationReanalysisPreparationOwner,
                       analysisID: UUID = UUID(),
                       owning: @MainActor (ObservationReanalysisLocalVideoInput) -> Void,
                       retaining: @escaping @MainActor @Sendable (ObservationReanalysisLocalVideoInput) -> Void = { _ in },
                       isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationReanalysisLocalVideoInput {
        try ObservationVideoManifest.validateDescriptions(descriptions)
        guard !descriptions.contains(where: { $0.unicodeScalars.contains(where: { $0.value == 0 }) }) else {
            throw MerianError.invalidResponse
        }
        let input = try ObservationReanalysisLocalVideoInput(choice: choice, analysisID: analysisID,
            descriptions: descriptions, files: files, container: container, startup: startup, borrowing: borrowing, store: store, ownership: ownership)
        owning(input)
        input.busy = true
        defer { input.busy = false }
        try await input.acquireCopiedInput(account: account, isCurrent: isCurrent, afterCopy: { retaining(input) })
        return input
    }

    private func acquireFence(cleanup: Bool = false) throws -> SharedMediaStoreReadFence {
        if let borrowing { return try borrowing.fence(container: container, cleanup: cleanup) }
        return try startup.acquireFence(container: container)
    }

    private func requireFence(cleanup: Bool = false) throws {
        guard let fence else { throw ObservationHistoryError.unavailable }
        try startup.require(container: container, fence: fence)
        try borrowing?.require(container: container, fence: fence, cleanup: cleanup)
    }

    private func readReceipt(cleanup: Bool = false) throws -> ObservationReanalysisInputReceipt {
        try requireFence(cleanup: cleanup)
        guard let receipt = try ObservationReanalysisInputPersistence.read(child: analysisID, container: container),
              receipt.ownerID == source.ownerID, receipt.parentID == source.observationID,
              receipt.childID == analysisID, receipt.planDigest == planDigest else { throw ObservationHistoryError.resultConflict }
        return receipt
    }

    private func acquireCopiedInput(account: ObservationHistoryCloudClient,
                                    isCurrent: @escaping @MainActor @Sendable () -> Bool,
                                    afterCopy: @escaping @MainActor @Sendable () -> Void = {}) async throws {
        let identity = OfflineQueueWork.Reanalysis(observationID: source.observationID, sourceAnalysisID: source.analysisID,
            analysisID: analysisID, ownerID: source.ownerID)
        try await ownership.perform(identity) { [self] tokenCurrent in
            let lease = try account.begin(source.ownerID)
            defer { account.finish(lease) }
            if fence == nil { fence = try acquireFence() }
            let current: @MainActor @Sendable () throws -> Void = {
                try Task.checkCancellation()
                guard !self.invalidated, tokenCurrent(), isCurrent(), account.isCurrent(lease),
                      lease.session.userID == self.source.ownerID else { throw ObservationHistoryError.accountChanged }
                try self.requireFence()
            }
            let validate: @MainActor @Sendable () throws -> Void = {
                try current()
                try self.choice.validate(container: self.container)
            }
            try validate()
            if copyAttempted {
                let receipt = try readReceipt()
                copied = try await store.recoverInput(receipt, read: { try validate(); return try self.readReceipt() })
            } else {
                copyAttempted = true
                try await store.initializeInputs(readState: {
                    try validate()
                    return try ObservationReanalysisInputPersistence.inspectForFreshPreparation(container: self.container)
                }, commit: { ledger in
                    try ObservationReanalysisInputPersistence.initialize(ledger, container: self.container, validate: { context in
                        try current(); try self.choice.validate(context: context)
                    })
                }, validate: validate)
                try validate()
                let request = ObservationReanalysisFileStore.InputRequest(ownerID: source.ownerID,
                    parentID: source.observationID, childID: analysisID, planDigest: planDigest)
                copied = try await store.createInput(request, inspect: {
                    try validate(); return try ObservationReanalysisInputPersistence.inspect(container: self.container)
                }, reserve: { receipt in
                    try ObservationReanalysisInputPersistence.reserve(receipt, container: self.container, validate: { context in
                        try current(); try self.choice.validate(context: context)
                    })
                }, advance: { before, after in
                    try ObservationReanalysisInputPersistence.advance(from: before, to: after, container: self.container, validate: current)
                }, validate: validate, copy: { [files, choice] descriptor in
                    await files.copyVideoInput(filename: choice.filename, ownedOutput: descriptor)
                })
            }
            // Preserve the existing post-copy handoff independently of early ownership.
            afterCopy()
            try validate()
            guard let copied else { throw ObservationHistoryError.unavailable }
            try await store.inputIsCurrent(copied, read: { try current(); return try self.readReceipt() })
            try validate()
            copyValidated = true
        }
    }

    /// One input and child identity survive preparation uncertainty. Once a
    /// cohort exists, retry reuses its exact bytes through the existing producer.
    /// After readiness, retries use existing-only complete-cohort recovery.
    func prepare(container: ModelContainer, account: ObservationHistoryCloudClient,
                 producer: ObservationVideoPreparationProducer, temporaryDirectory: URL,
                 isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationVideoPreparation.Verified {
        guard !busy, !invalidated, container === self.container else { throw ObservationHistoryError.unavailable }
        busy = true
        defer { busy = false }
        let lease = try account.begin(source.ownerID)
        defer { account.finish(lease) }
        if fence == nil { fence = try acquireFence() }
        // Passed into persistence transactions: never reenter source/database validation here.
        let current: @MainActor @Sendable () -> Bool = { [self] in
            !Task.isCancelled && !invalidated && isCurrent() &&
                lease.session.userID == source.ownerID && account.isCurrent(lease)
        }
        let check: @MainActor @Sendable () throws -> Void = { [self] in
            try Task.checkCancellation()
            guard current() else { throw ObservationHistoryError.accountChanged }
            try requireFence()
            try source.validate(container: container)
        }
        try check()
        guard container === self.container else { throw ObservationHistoryError.unavailable }
        try requireFence()
        if let preparation {
            _ = try await producer.prepare(preparation, source: source, cohort: retainedCohort,
                container: container, isCurrent: current)
            try check()
            retainedCohort = nil
            return try preparation.verified(source: source)
        }
        if !copyValidated {
            try await acquireCopiedInput(account: account, isCurrent: isCurrent)
            try check()
        }
        guard let copied else { throw ObservationHistoryError.unavailable }
        let store = store
        #if DEBUG
        let checkpoint = TestExecutionCoordinator.isRunningUnitTests ? inputPhaseCheckpoint : nil
        #endif
        let validate: @Sendable (ObservationVideoCohortPhase) async throws -> Void = { phase in
            try await check()
            try await store.inputIsCurrent(copied, read: { try self.readReceipt() })
            #if DEBUG
            try await checkpoint?(phase)
            #endif
            try await check()
        }
        try await validate(.retained)
        let cohort = try await ObservationVideoCohortPreparer(validate: validate).prepare(source: copied.url,
            directory: temporaryDirectory, observationID: source.observationID, analysisID: analysisID,
            sourceAnalysisID: source.analysisID, descriptions: descriptions,
            cropCenterBasisPoints: 5000, inferenceLongEdge: 768)
        try check()
        let prepared = try ObservationVideoPreparation(request: cohort.request, source: source)
        preparation = prepared
        retainedCohort = cohort
        _ = try await producer.prepare(prepared, source: source, cohort: cohort,
            container: container, isCurrent: current)
        try check()
        retainedCohort = nil
        return try prepared.verified(source: source)
    }

    /// No receipt/absence claim: only this consumer's actual runtime occupancy.
    var isRuntimeQuiescent: Bool { !busy && copied == nil && fence == nil }

    /// Exact input retirement is independent of the former source/account. A
    /// failed cleanup retains durable ownership, but actual-exit runtime locks
    /// are released so an authorized outer full-library purge cannot deadlock.
    func discardCopiedInput() async -> Bool {
        invalidated = true
        guard !busy else { return false }
        if copiedInputReleased { return true }
        busy = true
        defer { busy = false }
        retainedCohort = nil
        do {
            if !copyAttempted { copiedInputReleased = true; fence = nil; return true }
            if fence == nil { fence = try acquireFence(cleanup: true) }
            try requireFence(cleanup: true)
            try await store.eraseInput(child: analysisID, token: copied,
                read: { try self.readReceipt(cleanup: true) }, advance: { before, after in
                    try ObservationReanalysisInputPersistence.advance(from: before, to: after, container: self.container,
                        validate: { try self.requireFence(cleanup: true) })
                })
            copied = nil; fence = nil; copiedInputReleased = true
            return true
        } catch {
            // Releasing a lease is never a claim that its bytes or receipt are gone.
            if let copied {
                guard await store.releaseInputLease(copied) else { return false }
                self.copied = nil
            }
            fence = nil
            return false
        }
    }
}
