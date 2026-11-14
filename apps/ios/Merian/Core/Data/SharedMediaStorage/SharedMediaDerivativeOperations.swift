import Foundation

/// Uses the inbox owner's existing task, account lease, repository and I/O actor.
/// This helper owns no independent coordinator, writer, cache or inference path.
@MainActor
struct SharedMediaDerivativeOperations {
    let storage: SharedMediaStorageRepository
    let io: SharedMediaInboxDestinationIO
    let check: @MainActor () throws -> Void

    func prepare(_ original: PhotoOriginalReference, ai: Data, display: Data) async throws -> SharedMediaDerivativeRequest {
        let aiInput = try await io.prepareDerivative(ai, role: .aiInput); try check()
        let displayInput = try await io.prepareDerivative(display, role: .display); try check()
        try await verifyOriginal(original)
        return try storage.inboxRead { try $0.derivatives.prepare(original, ai: aiInput, display: displayInput) }
    }

    func replace(_ request: SharedMediaDerivativeRequest, ai: Data, display: Data) async throws -> SharedMediaDerivativeReceipt {
        try check()
        if let saved = try saved(request) {
            guard saved.phase == "ready" else { throw PhotoPreparationFailure.cleanupPending }
            return try await receipt(saved)
        }
        // Both payloads are checked before any old pair is retired. A saved edit
        // is recovery-only and never re-enters this fresh-write path.
        try await io.validateDerivative(ai, input: request.ai); try check()
        try await io.validateDerivative(display, input: request.display); try check()
        try await verifyOriginal(request.original)
        try await io.validate(storage.inboxRead { try $0.photos.inventory() }); try check()
        let previous = try storage.inboxRead { try $0.derivatives.all() }.first { $0.request.id == request.previousPairID }
        var old: [SharedMediaDerivativeInspection] = []
        if let previous {
            for work in previous.work {
                old.append(try await io.inspectRetirement(work)); try check()
            }
        }
        _ = try transaction(request, before: .beforePairPlanSave, after: .afterPairPlanSave) { try $0.plan(request, old: old) }
        do {
            if let previous { try await release(previous.request) }
            var pair = try transaction(request, before: .beforeReservationSave, after: .afterReservationSave, freeSpace: true) { try $0.reserve(request) }
            for input in request.inputs {
                guard let work = pair.work.first(where: { $0.input == input }) else { throw SharedMediaStorageFailure.conflict }
                let partial = try await io.begin(work); try check()
                pair = try transaction(request, before: .beforeIdentitySave, after: .afterIdentitySave) { try $0.partial(partial) }
                guard let writing = pair.work.first(where: { $0.input == input }) else { throw SharedMediaStorageFailure.conflict }
                let completion = try await io.write(input.role == "aiInput" ? ai : display, work: writing); try check()
                pair = try transaction(request, before: .beforeCompletionSave, after: .afterCompletionSave) { try $0.complete(completion) }
            }
            try await verifyOriginal(request.original)
            pair = try transaction(request, before: .beforePairPublishSave, after: .afterPairPublishSave) { try $0.publish(request) }
            return try await receipt(pair)
        } catch {
            // Actor writes have actually returned. Closing liabilities is allowed
            // after cancellation/account loss; neither deletion nor retry is.
            try? await close(request, checkingAccount: false)
            throw error
        }
    }

    func ready(_ request: SharedMediaDerivativeRequest) async throws -> SharedMediaDerivativeReceipt {
        guard let pair = try saved(request), pair.phase == "ready" else { throw PhotoPreparationFailure.cleanupPending }
        return try await receipt(pair)
    }

    func recover(ownerID: UUID) async throws -> [SharedMediaDerivativeRecovery] {
        try await io.prune(storage.inboxRead { try $0.photos.inventory() }); try check()
        let pairs = try storage.inboxRead { try $0.derivatives.all() }.filter { $0.request.original.ownerID == ownerID }
        var result: [SharedMediaDerivativeRecovery] = []
        for initial in pairs {
            try check()
            // A previous retiring pair can have been released by this pass.
            guard let current = try saved(initial.request) else { continue }
            do {
                if current.phase == "retiring" { try await release(current.request); continue }
                if current.phase == "planned" { result.append(.incomplete(current.request)); continue }
                if current.phase == "ready" { result.append(.ready(try await receipt(current))); continue }
                try await close(current.request)
                var pair = try required(current.request)
                for work in pair.work {
                    if let proof = try await io.recover(work) {
                        try check()
                        pair = try transaction(pair.request, before: .beforeCompletionSave, after: .afterCompletionSave) { try $0.complete(proof) }
                    } else { try check() }
                }
                if pair.work.allSatisfy({ $0.phase == "completed" }) {
                    try await verifyOriginal(pair.request.original)
                    pair = try transaction(pair.request, before: .beforePairPublishSave, after: .afterPairPublishSave) { try $0.publish(pair.request) }
                    result.append(.ready(try await receipt(pair)))
                } else { result.append(.incomplete(pair.request)) }
            } catch { try check(); result.append(.conflict(current.request)) }
        }
        return result
    }

    func discard(_ request: SharedMediaDerivativeRequest) async throws {
        try check()
        var pair = try required(request)
        if let previousID = request.previousPairID,
           let previous = try storage.inboxRead({ try $0.derivatives.all() }).first(where: { $0.request.id == previousID }) {
            guard previous.phase == "retiring" else { throw SharedMediaStorageFailure.conflict }
            try await release(previous.request)
        }
        if pair.phase != "retiring" {
            try await close(request); pair = try required(request)
            var inspections: [SharedMediaDerivativeInspection] = []
            for work in pair.work { inspections.append(try await io.inspectRetirement(work)); try check() }
            _ = try transaction(request, before: .beforeRetirementSave, after: .afterRetirementSave) { try $0.retire(request, inspections: inspections) }
        }
        try await release(request)
        try await io.prune(storage.inboxRead { try $0.photos.inventory() }); try check()
    }

    private func close(_ request: SharedMediaDerivativeRequest, checkingAccount: Bool = true) async throws {
        let pair = try required(request)
        guard pair.phase == "writing" else { return }
        for work in pair.work {
            let proof = try await io.closure(work)
            if checkingAccount { try check() }
            _ = try transaction(request, before: .beforeClosureSave, after: .afterClosureSave, checkingAccount: checkingAccount) { try $0.close(proof) }
        }
    }

    private func release(_ request: SharedMediaDerivativeRequest) async throws {
        try check()
        let intents = try storage.derivativeRetirements(request)
        var proofs: [SharedMediaDerivativeRelease] = []
        for intent in intents { proofs.append(try await io.release(intent)); try check() }
        do {
            try storage.handoffWrite(before: .beforeReleaseSave, after: .afterReleaseSave) { try $0.derivatives.release(request, proofs: proofs) }
        } catch { guard try saved(request) == nil else { throw error } }
    }

    private func receipt(_ pair: SharedMediaDerivativePair) async throws -> SharedMediaDerivativeReceipt {
        try check()
        guard pair.phase == "ready", let revision = pair.publishedRevision else { throw PhotoPreparationFailure.cleanupPending }
        try await verifyOriginal(pair.request.original)
        for work in pair.work {
            guard work.phase == "completed", let identity = work.finalIdentity else { throw SharedMediaStorageFailure.conflict }
            _ = try await io.read(work.file, identity: identity); try check()
        }
        guard try saved(pair.request) == pair else { throw SharedMediaStorageFailure.stale }
        return .init(pairID: pair.request.id, original: pair.request.original, publishedRevision: revision,
                     ai: pair.work[0].file, display: pair.work[1].file)
    }

    private func verifyOriginal(_ original: PhotoOriginalReference) async throws {
        let (file, identity) = try storage.inboxRead { ledger in
            let file = try ledger.photos.resolve(original), inventory = try ledger.photos.inventory()
            guard let identity = inventory.identities[file.assetID] else { throw SharedMediaStorageFailure.conflict }
            return (file, identity)
        }
        _ = try await io.read(file, identity: identity); try check()
    }
    private func saved(_ request: SharedMediaDerivativeRequest) throws -> SharedMediaDerivativePair? {
        try storage.inboxRead { try $0.derivatives.saved(request) }
    }
    private func required(_ request: SharedMediaDerivativeRequest) throws -> SharedMediaDerivativePair {
        guard let pair = try saved(request) else { throw SharedMediaStorageFailure.stale }; return pair
    }
    private func transaction(_ request: SharedMediaDerivativeRequest, before: SharedMediaInboxHandoffBoundary,
                             after: SharedMediaInboxHandoffBoundary, freeSpace: Bool = false, checkingAccount: Bool = true,
                             _ body: (SharedMediaDerivativeLedger) throws -> SharedMediaDerivativePair) throws -> SharedMediaDerivativePair {
        if checkingAccount { try check() }
        var expected: SharedMediaDerivativePair?
        do {
            let result = try storage.handoffWrite(before: before, after: after, requiresFreeSpace: freeSpace) {
                let pair = try body($0.derivatives); expected = pair; return pair
            }
            if checkingAccount { try check() }
            return result
        } catch {
            guard let expected, try saved(request) == expected else { throw error }
            if checkingAccount { try check() }
            return expected
        }
    }
}
