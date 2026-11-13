import Foundation
import SwiftData

/// Scoped preparation under one retained app owner. Only a newly acknowledged
/// reservation can enter processing; saved attempts never authorize replay.
@MainActor
// The full name identifies the exact native operation and its ownership boundary.
// swiftlint:disable:next type_name
final class SharedMediaNativeAppPreparationOperations {
    private let container: ModelContainer
    private let authority: SharedMediaNativeAppOperationAuthority
    private let expected: SharedMediaNativeAppEligibility.Header
    private let facts: SharedMediaNativeAppMetadataFacts
    private let availableBytes: () throws -> Int64
    private let boundary: (SharedMediaNativePreparationBoundary) throws -> Void
    private let io: SharedMediaNativeOriginalIO
    private let focusFactory: ImageFocusWorkFactory
    private let verifyProof: (SharedMediaPhotoRetirementInspection) throws -> Void
    private let verifyPlannedAbsence: (SharedMediaNativePlannedAbsence) throws -> Void
    private let fileBinding: SharedMediaNativeBinding
    private let verifyCompletion: (SharedMediaNativePairCompletion) throws -> Void
    private let verifyPartial: (SharedMediaNativePairPartial) throws -> Void
    private let verifyInspection: (SharedMediaNativePairInspection) throws -> Void
    private let verifyAbsence: (SharedMediaNativePairAbsence) throws -> Void
    private var consumed = false
    private init(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                 expected: SharedMediaNativeAppEligibility.Header, facts: SharedMediaNativeAppMetadataFacts,
                 availableBytes: @escaping () throws -> Int64, boundary: @escaping (SharedMediaNativePreparationBoundary) throws -> Void,
                 io: SharedMediaNativeOriginalIO, focusFactory: ImageFocusWorkFactory,
                 verifyProof: @escaping (SharedMediaPhotoRetirementInspection) throws -> Void,
                 verifyPlannedAbsence: @escaping (SharedMediaNativePlannedAbsence) throws -> Void,
                 fileBinding: SharedMediaNativeBinding, verifyPartial: @escaping (SharedMediaNativePairPartial) throws -> Void,
                 verifyCompletion: @escaping (SharedMediaNativePairCompletion) throws -> Void,
                 verifyInspection: @escaping (SharedMediaNativePairInspection) throws -> Void,
                 verifyAbsence: @escaping (SharedMediaNativePairAbsence) throws -> Void) {
        self.container = container; self.authority = authority; self.expected = expected; self.facts = facts
        self.availableBytes = availableBytes; self.boundary = boundary
        self.io = io; self.focusFactory = focusFactory; self.verifyProof = verifyProof; self.verifyPlannedAbsence = verifyPlannedAbsence
        self.verifyInspection = verifyInspection; self.verifyAbsence = verifyAbsence
        self.fileBinding = fileBinding; self.verifyPartial = verifyPartial; self.verifyCompletion = verifyCompletion
    }
    static func audited(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                        availableBytes: @escaping () throws -> Int64,
                        boundary: @escaping (SharedMediaNativePreparationBoundary) throws -> Void,
                        io: SharedMediaNativeOriginalIO, focusFactory: ImageFocusWorkFactory,
                        verifyProof: @escaping (SharedMediaPhotoRetirementInspection) throws -> Void,
                        verifyPlannedAbsence: @escaping (SharedMediaNativePlannedAbsence) throws -> Void,
                        fileBinding: SharedMediaNativeBinding, verifyPartial: @escaping (SharedMediaNativePairPartial) throws -> Void,
                        verifyCompletion: @escaping (SharedMediaNativePairCompletion) throws -> Void,
                        verifyInspection: @escaping (SharedMediaNativePairInspection) throws -> Void,
                        verifyAbsence: @escaping (SharedMediaNativePairAbsence) throws -> Void) async throws -> SharedMediaNativeAppPreparationOperations {
        let expected = try authority.header(container)
        _ = try await SharedMediaNativeScopedAudit(app: container, profile: authority.profile, expected: expected.inventory,
            check: { guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale } },
            betweenPages: { await Task.yield() }).run()
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        return .init(container: container, authority: authority, expected: expected,
            facts: try SharedMediaNativeAppMetadataFacts.capture(context, profile: authority.profile), availableBytes: availableBytes, boundary: boundary,
            io: io, focusFactory: focusFactory, verifyProof: verifyProof, verifyPlannedAbsence: verifyPlannedAbsence, fileBinding: fileBinding, verifyPartial: verifyPartial, verifyCompletion: verifyCompletion, verifyInspection: verifyInspection, verifyAbsence: verifyAbsence)
    }
    static func audited(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                        availableBytes: @escaping () throws -> Int64,
                        boundary: @escaping (SharedMediaNativePreparationBoundary) throws -> Void,
                        io: SharedMediaNativeOriginalIO, focusFactory: ImageFocusWorkFactory,
                        files: PhotoPreparationLockedFiles, binding: SharedMediaNativeBinding,
                        observed: @escaping (SharedMediaPhotoRetirementInspection) -> Void) async throws -> SharedMediaNativeAppPreparationOperations {
        try await audited(container: container, authority: authority, availableBytes: availableBytes, boundary: boundary,
            io: io, focusFactory: focusFactory, verifyProof: { try files.requireCurrentSharedInspection($0); observed($0) },
            verifyPlannedAbsence: { try files.requireCurrentPlannedAbsence($0, binding: binding) }, fileBinding: binding,
            verifyPartial: { try files.requireCurrentPairPartial($0, binding: binding) },
            verifyCompletion: { try files.requireCurrentPairCompletion($0, binding: binding) },
            verifyInspection: { try files.requireCurrentPairInspection($0, binding: binding) },
            verifyAbsence: { try files.requireCurrentPairAbsence($0, binding: binding) })
    }
    private func mutation(_ packageID: UUID, action: SharedMediaNativeAppPreparationWitness.Action) throws -> SharedMediaNativePreparationMutation {
        guard !consumed, facts.packages[packageID] != nil, facts.members[packageID] != nil,
              facts.consumers[packageID] == nil else { throw SharedMediaStorageFailure.closed }
        try boundary(.beforeReadback)
        let witness = SharedMediaNativeAppPreparationWitness(authority: authority, expected: expected, facts: facts, action: action)
        return try .init(container: container, packageID: packageID, witness: witness)
    }
    func reserve(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) throws -> SharedMediaNativePreparationAttempt {
        try facts.requireMutable(original.packageID)
        let mutation = try mutation(original.packageID, action: .reserve)
        let request = try mutation.request(original: original, recipe: recipe)
        consumed = true
        do {
            try mutation.reserve(request, availableBytes: availableBytes(), beforeSave: { try self.boundary(.beforeSave) }, afterSave: { try self.boundary(.afterSave) })
        } catch {
            let failure = error
            do { try boundary(.beforeReadback); try mutation.acknowledgeApp() } catch { throw failure }
        }
        try boundary(.beforeReadback); try mutation.acknowledgeApp()
        return request
    }
    /// There is deliberately no entry accepting a saved attempt or caller output.
    /// The once-only operation is consumed by reserve before any processor await.
    func prepareAndPlan(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) async throws -> SharedMediaNativePairPlan {
        try await freshPlan(original: original, recipe: recipe).0
    }
    private func freshPlan(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) async throws
        -> (SharedMediaNativePairPlan, SharedMediaNativePreparedOutputs) {
        let attempt = try reserve(original: original, recipe: recipe)
        let current = try await Self.audited(container: container, authority: authority, availableBytes: availableBytes,
            boundary: boundary, io: io, focusFactory: focusFactory, verifyProof: verifyProof, verifyPlannedAbsence: verifyPlannedAbsence, fileBinding: fileBinding, verifyPartial: verifyPartial, verifyCompletion: verifyCompletion, verifyInspection: verifyInspection, verifyAbsence: verifyAbsence)
        let witness = SharedMediaNativeAppPreparationWitness(authority: authority, expected: current.expected, facts: current.facts, action: .inspect)
        try SharedMediaNativePreparationMutation(container: container, packageID: original.packageID, witness: witness).result(attempt)
        try Task.checkCancellation()
        let outputs = try await io.preparePhoto(attempt, focusFactory: focusFactory)
        try witness.validate(container); try Task.checkCancellation()
        let proof = try await io.inspect(attempt.original.file)
        try witness.validate(container); try Task.checkCancellation()
        guard proof.identity == attempt.original.descriptor else { throw SharedMediaStorageFailure.stale }
        try verifyProof(proof)
        let planWitness = SharedMediaNativeAppPairPlanWitness(preparation: witness, attempt: attempt, fileEpoch: proof.epoch,
            verifyOriginal: { try self.verifyProof(proof) }, beforeReadback: { try self.boundary(.beforeReadback) })
        let mutation = try SharedMediaNativePairPlanMutation(container: container, witness: planWitness, pairID: outputs.intent.pairID)
        let plan = try mutation.plan(outputs, availableBytes: availableBytes(), beforeSave: { try self.boundary(.beforePairSave) },
            afterSave: { try self.boundary(.afterPairSave) })
        return (plan, outputs)
    }
    /// Fresh outputs remain private for the entire held operation. Saved plans
    /// cannot enter this path and cannot supply replacement bytes.
    func prepareAndDeliver(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) async throws -> SharedMediaNativePairFileState {
        let (plan, output) = try await freshPlan(original: original, recipe: recipe)
        var current = try await deliveryState(plan)
        let absent = try await io.inspectPlannedPairAbsent(current)
        guard absent.count == 2, Set(absent.map(\.workID)) == Set(current.work.map(\.id)) else { throw SharedMediaStorageFailure.conflict }
        current = try await transition(current, action: .reserve, seal: {
            for proof in absent { try self.verifyPlannedAbsence(proof) }
        })
        for (input, data) in [(output.intent.ai, output.ai), (output.intent.display, output.display)] {
            _ = try authority.header(container); try Task.checkCancellation()
            let partial = try await io.beginPair(current, workID: input.id)
            _ = try authority.header(container); try Task.checkCancellation()
            current = try await transition(current, action: .partial(partial), seal: { try self.verifyPartial(partial) })
            _ = try authority.header(container); try Task.checkCancellation()
            let complete = try await io.writePair(data, state: current, workID: input.id)
            _ = try authority.header(container); try Task.checkCancellation()
            let observed = try await io.inspect(complete.file)
            guard observed.identity.file == complete.identity.exact else { throw SharedMediaStorageFailure.conflict }
            current = try await transition(current, action: .complete(complete), seal: { try self.verifyProof(observed); try self.verifyCompletion(complete) })
        }
        let (completed, observed) = try await publicationObservations(current)
        return try await transition(current, action: .publish(completed), seal: {
            for proof in observed { try self.verifyProof(proof) }
            for proof in completed { try self.verifyCompletion(proof) }
        })
    }
    private func publicationObservations(_ state: SharedMediaNativePairFileState) async throws
        -> ([SharedMediaNativePairCompletion], [SharedMediaPhotoRetirementInspection]) {
        let original = try state.intent().preparation.original
        let originalProof = try await io.inspect(original.file)
        guard originalProof.identity == original.descriptor else { throw SharedMediaStorageFailure.conflict }
        var completed: [SharedMediaNativePairCompletion] = []
        var observed: [SharedMediaPhotoRetirementInspection] = [originalProof]
        for work in state.work {
            _ = try authority.header(container); try Task.checkCancellation()
            // Fresh read-only verification, never recovery/rename of saved bytes.
            let proof = try await io.inspectCompletedPair(state, workID: work.id)
            completed.append(proof)
            let file = try await io.inspect(proof.file)
            guard file.identity.file == proof.identity.exact else { throw SharedMediaStorageFailure.conflict }
            observed.append(file)
        }
        return (completed, observed)
    }
    /// Cold recovery has no data/provider input and never enters freshPlan,
    /// beginPair or writePair. An incomplete or unbound output remains held.
    func recoverFiles(packageID: UUID, pairID: UUID) async throws -> SharedMediaNativePairFileState {
        try facts.requireMutable(packageID)
        guard !consumed else { throw SharedMediaStorageFailure.closed }; consumed = true
        var state = try recoveryState(packageID: packageID, pairID: pairID)
        guard ["writing", "ready"].contains(state.phase) else { throw SharedMediaStorageFailure.closed }
        let original = try state.intent().preparation.original
        let originalProof = try await io.inspect(original.file)
        guard originalProof.identity == original.descriptor else { throw SharedMediaStorageFailure.conflict }
        for id in state.work.map(\.id) {
            let current = try await refresh()
            guard try current.recoveryState(packageID: packageID, pairID: pairID) == state else { throw SharedMediaStorageFailure.stale }
            try verifyProof(originalProof)
            let (work, _) = try state.selected(id)
            guard ["writing", "completed"].contains(work.phase) else { return state }
            if work.phase == "completed" { continue }
            guard let completion = try await io.recoverPair(state, workID: id) else {
                let current = try await refresh()
                guard try current.recoveryState(packageID: packageID, pairID: pairID) == state else { throw SharedMediaStorageFailure.stale }
                return state
            }
            _ = try authority.header(container); try Task.checkCancellation()
            let observed = try await io.inspect(completion.file)
            guard observed.identity.file == completion.identity.exact else { throw SharedMediaStorageFailure.conflict }
            state = try await recoverTransition(state, action: .completeSaved(completion), seal: {
                try self.verifyProof(originalProof); try self.verifyProof(observed); try self.verifyCompletion(completion)
            })
        }
        let (completed, observed) = try await publicationObservations(state)
        let seal = {
            for proof in observed { try self.verifyProof(proof) }
            for proof in completed { try self.verifyCompletion(proof) }
        }
        if state.phase == "ready" {
            let current = try await refresh()
            guard try current.recoveryState(packageID: packageID, pairID: pairID) == state else { throw SharedMediaStorageFailure.stale }
            try seal(); return state
        }
        return try await recoverTransition(state, action: .publishSaved(completed), seal: seal)
    }
    /// Closure is durably acknowledged before disposal. The same saved closure
    /// may reconcile absent files; a released old ID cannot mint new work.
    func retireFiles(packageID: UUID, pairID: UUID) async throws {
        try facts.requireMutable(packageID)
        guard !consumed else { throw SharedMediaStorageFailure.closed }; consumed = true
        var state = try recoveryState(packageID: packageID, pairID: pairID)
        guard ["writing", "ready", "retiring"].contains(state.phase) else { throw SharedMediaStorageFailure.closed }
        if state.phase != "retiring" {
            var inspections: [SharedMediaNativePairInspection] = []
            for work in state.work {
                _ = try authority.header(container); try Task.checkCancellation()
                inspections.append(try await io.inspectPair(state, workID: work.id))
            }
            let seals = inspections
            let owner = try await retirementOwner(state, action: .retire(inspections), seal: {
                for proof in seals { try self.verifyInspection(proof) }
            })
            guard let saved = try owner.applyApp(beforeSave: { try self.boundary(.beforeFileRetire) },
                afterSave: { try self.boundary(.afterFileRetire) }) else { throw SharedMediaStorageFailure.conflict }
            state = saved
        }
        let owner = try await retirementOwner(state, action: .inspect, seal: {})
        let disposal = try owner.disposal(state)
        var absent: [SharedMediaNativePairAbsence] = []
        for work in state.work {
            _ = try authority.header(container); try Task.checkCancellation()
            try facts.requireMutable(packageID)
            absent.append(try await io.releasePair(disposal, workID: work.id))
            _ = try authority.header(container); try Task.checkCancellation()
        }
        let seals = absent
        let release = try await retirementOwner(state, action: .release(absent), seal: {
            for proof in seals { try self.verifyAbsence(proof) }
        })
        _ = try release.applyApp(beforeSave: { try self.boundary(.beforeFileRelease) },
            afterSave: { try self.boundary(.afterFileRelease) })
    }
    private func retirementOwner(_ state: SharedMediaNativePairFileState, action: SharedMediaNativeAppPairRetirementWitness.Action,
                                 seal: @escaping () throws -> Void) async throws -> SharedMediaNativePairRetirementOwner {
        let current = try await refresh()
        try current.facts.requireMutable(state.plan.packageID)
        let preparation = SharedMediaNativeAppPreparationWitness(authority: authority, expected: current.expected, facts: current.facts, action: .inspect)
        return try .init(container: container, witness: .init(preparation: preparation, state: state,
            binding: fileBinding, action: action, seal: seal, beforeReadback: { try self.boundary(.beforeReadback) }))
    }
    private func recoveryState(packageID: UUID, pairID: UUID) throws -> SharedMediaNativePairFileState {
        let preparation = SharedMediaNativeAppPreparationWitness(authority: authority, expected: expected, facts: facts, action: .inspect)
        return try SharedMediaNativeAppPairRecoveryWitness.currentState(container, preparation: preparation, packageID: packageID, pairID: pairID)
    }
    private func recoverTransition(_ state: SharedMediaNativePairFileState, action: SharedMediaNativeAppPairRecoveryWitness.Action,
                                   seal: @escaping () throws -> Void) async throws -> SharedMediaNativePairFileState {
        let current = try await refresh()
        try current.facts.requireMutable(state.plan.packageID)
        let preparation = SharedMediaNativeAppPreparationWitness(authority: authority, expected: current.expected, facts: current.facts, action: .inspect)
        let witness = SharedMediaNativeAppPairRecoveryWitness(preparation: preparation, state: state,
            binding: fileBinding, action: action, seal: seal, beforeReadback: { try self.boundary(.beforeReadback) })
        return try SharedMediaNativePairFileMutation(container: container, recovery: witness).applyApp(availableBytes: availableBytes,
            beforeSave: { try self.boundary(action.transition.boundaries.0) }, afterSave: { try self.boundary(action.transition.boundaries.1) })
    }
    #if DEBUG
    func setFileFault(_ fault: (@Sendable (SharedMediaInboxHandoffBoundary) throws -> Void)?) async { await io.setPairFault(fault) }
    #endif
    private func deliveryState(_ plan: SharedMediaNativePairPlan) async throws -> SharedMediaNativePairFileState {
        let current = try await refresh()
        let witness = SharedMediaNativeAppPreparationWitness(authority: authority, expected: current.expected, facts: current.facts, action: .inspect)
        return try SharedMediaNativeAppPairPlanClosure.state(container, preparation: witness, plan: plan)
    }
    private func refresh() async throws -> SharedMediaNativeAppPreparationOperations {
        try await Self.audited(container: container, authority: authority, availableBytes: availableBytes,
            boundary: boundary, io: io, focusFactory: focusFactory, verifyProof: verifyProof,
            verifyPlannedAbsence: verifyPlannedAbsence, fileBinding: fileBinding, verifyPartial: verifyPartial, verifyCompletion: verifyCompletion, verifyInspection: verifyInspection, verifyAbsence: verifyAbsence)
    }
    private func transition(_ state: SharedMediaNativePairFileState, action: SharedMediaNativeAppPairAction,
                            seal: @escaping () throws -> Void) async throws -> SharedMediaNativePairFileState {
        let current = try await refresh()
        try current.facts.requireMutable(state.plan.packageID)
        let preparation = SharedMediaNativeAppPreparationWitness(authority: authority, expected: current.expected, facts: current.facts, action: .inspect)
        let witness = SharedMediaNativeAppPairFileWitness(preparation: preparation, state: state,
            binding: fileBinding, action: action, seal: seal, beforeReadback: { try self.boundary(.beforeReadback) })
        return try SharedMediaNativePairFileMutation(container: container, witness: witness).applyApp(availableBytes: availableBytes,
            beforeSave: { try self.boundary(action.boundaries.0) }, afterSave: { try self.boundary(action.boundaries.1) })
    }
    /// A mutable-ready projection grants no write, recovery or execution authority.
    func readPreparedPhotos(expectedMetadata metadata: SharedMediaNativeAppMetadataRequest, pairIDs: [UUID]) async throws -> SharedMediaNativePhotoReadback {
        guard !consumed, (1...2).contains(pairIDs.count), Set(pairIDs).count == pairIDs.count else { throw SharedMediaStorageFailure.closed }
        let packageID = metadata.package.id
        try facts.requireMutable(packageID)
        let witness = SharedMediaNativeAppPreparationWitness(authority: authority, expected: expected, facts: facts, action: .inspect)
        func validate() throws -> [SharedMediaNativePairFileState] {
            try Task.checkCancellation(); try boundary(.beforeReadback); try witness.validate(container)
            guard metadata.profile == authority.profile, metadata.header == expected,
                  facts.packages[packageID] == metadata.package, facts.members[packageID] == metadata.member,
                  metadata.envelope == metadata.package.envelope else { throw SharedMediaStorageFailure.stale }
            let states = try pairIDs.map { try recoveryState(packageID: packageID, pairID: $0) }
            try SharedMediaNativePhotoReadback.validate(metadata: metadata, pairs: states)
            return states
        }
        let states = try validate()
        var photos: [SharedMediaNativePhotoReadback.Photo] = [], proofs: [SharedMediaNativePairCompletion] = []
        for state in states {
            let intent = try state.intent()
            let (ai, aiProof) = try await io.readCompletedPair(state, workID: intent.ai.id)
            guard try validate() == states else { throw SharedMediaStorageFailure.stale }
            proofs.append(aiProof)
            let (display, displayProof) = try await io.readCompletedPair(state, workID: intent.display.id)
            guard try validate() == states else { throw SharedMediaStorageFailure.stale }
            proofs.append(displayProof)
            photos.append(.init(pair: state, original: intent.preparation.original.reference, ai: ai, display: display))
        }
        // Revalidate the complete cohort after the last actor hop, including
        // earlier files that could have changed while later files were read.
        guard try validate() == states else { throw SharedMediaStorageFailure.stale }
        for proof in proofs { try verifyCompletion(proof) }
        #if DEBUG
        try boundary(.afterPhotoReadbackSeal)
        #endif
        guard try validate() == states else { throw SharedMediaStorageFailure.stale }
        return .init(metadata: metadata, photos: photos)
    }
    func savedPlan(packageID: UUID, pairID: UUID) throws -> SharedMediaNativePairPlan {
        guard !consumed, facts.packages[packageID] != nil, facts.consumers[packageID] == nil else { throw SharedMediaStorageFailure.closed }
        try boundary(.beforeReadback)
        let witness = SharedMediaNativeAppPreparationWitness(authority: authority, expected: expected, facts: facts, action: .inspect)
        try witness.validate(container)
        let context = ModelContext(container); context.autosaveEnabled = false
        let inventoryID = authority.profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let package = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        return try SharedMediaNativePairPlanGraph.state(context: context, inventory: inventory, package: package, member: member, pairID: pairID)
    }
    func abandonPlan(_ plan: SharedMediaNativePairPlan) async throws {
        try facts.requireMutable(plan.packageID)
        let pairID = try SharedMediaNativeDerivativeIntent.decode(plan.intent.bytes).pairID
        guard try savedPlan(packageID: plan.packageID, pairID: pairID) == plan else { throw SharedMediaStorageFailure.stale }
        let preparation = SharedMediaNativeAppPreparationWitness(authority: authority, expected: expected, facts: facts, action: .inspect)
        let state = try SharedMediaNativeAppPairPlanClosure.state(container, preparation: preparation, plan: plan)
        consumed = true
        let proofs = try await io.inspectPlannedPairAbsent(state)
        try preparation.validate(container); try Task.checkCancellation()
        guard proofs.count == 2, Set(proofs.map(\.workID)) == Set(state.work.map(\.id)),
              proofs.allSatisfy({ $0.state == state }) else { throw SharedMediaStorageFailure.conflict }
        let witness = SharedMediaNativeAppPairPlanClosureWitness(preparation: preparation, state: state,
            verifyAbsent: { for proof in proofs { try self.verifyPlannedAbsence(proof) } })
        try SharedMediaNativeAppPairPlanClosure(container: container, witness: witness).close(
            beforeSave: { try self.boundary(.beforePlanClosureSave) }, afterSave: { try self.boundary(.afterPlanClosureSave) },
            beforeReadback: { try self.boundary(.beforeReadback) })
    }
    func active(packageID: UUID) throws -> SharedMediaNativePreparationAttempt? {
        try mutation(packageID, action: .inspect).activeAttempt()
    }
    func abandon(_ request: SharedMediaNativePreparationAttempt) throws {
        let mutation = try mutation(request.original.reference.packageID, action: .abandon(request))
        consumed = true
        do {
            try mutation.abandon(request, beforeSave: { try self.boundary(.beforeSave) }, afterSave: { try self.boundary(.afterSave) })
        } catch {
            let failure = error
            do { try boundary(.beforeReadback); try mutation.acknowledgeApp() } catch { throw failure }
        }
        try boundary(.beforeReadback); try mutation.acknowledgeApp()
    }
}

/// The exact action is sealed after the complete audit. In particular, a cold
/// closure action cannot authorize reservation or processing with the old epoch.
@MainActor
struct SharedMediaNativeAppPreparationWitness {
    enum Action: Equatable { case inspect, reserve, abandon(SharedMediaNativePreparationAttempt) }
    let authority: SharedMediaNativeAppOperationAuthority
    let expected: SharedMediaNativeAppEligibility.Header
    let facts: SharedMediaNativeAppMetadataFacts
    let action: Action
    fileprivate init(authority: SharedMediaNativeAppOperationAuthority, expected: SharedMediaNativeAppEligibility.Header,
                     facts: SharedMediaNativeAppMetadataFacts, action: Action) {
        self.authority = authority; self.expected = expected; self.facts = facts; self.action = action
    }
    func validate(_ container: ModelContainer) throws {
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        guard try SharedMediaNativeAppMetadataFacts.capture(context, profile: authority.profile) == facts else { throw SharedMediaStorageFailure.stale }
    }
}

/// Minted only after the fresh reservation and concrete processor return within
/// the same retained operation. Neither a persisted attempt nor raw output mints it.
@MainActor
struct SharedMediaNativeAppPairPlanWitness {
    let preparation: SharedMediaNativeAppPreparationWitness
    let attempt: SharedMediaNativePreparationAttempt
    let fileEpoch: UUID
    let verifyOriginal: () throws -> Void
    let beforeReadback: () throws -> Void
    fileprivate init(preparation: SharedMediaNativeAppPreparationWitness, attempt: SharedMediaNativePreparationAttempt, fileEpoch: UUID,
                     verifyOriginal: @escaping () throws -> Void, beforeReadback: @escaping () throws -> Void) {
        self.preparation = preparation; self.attempt = attempt; self.fileEpoch = fileEpoch; self.verifyOriginal = verifyOriginal; self.beforeReadback = beforeReadback
    }
    func validate(_ container: ModelContainer) throws {
        try Task.checkCancellation(); try preparation.validate(container)
        guard attempt.writerEpoch == preparation.authority.writerEpoch else { throw SharedMediaStorageFailure.stale }
        try SharedMediaNativePreparationMutation(container: container, packageID: attempt.original.reference.packageID, witness: preparation).result(attempt)
        let context = ModelContext(container); context.autosaveEnabled = false
        let id = preparation.authority.profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory, ownerID: preparation.authority.profile.ownerID, format: .appV2)
    }
}

/// Cold closure authority is separate from fresh-processing authority. The saved
/// work epoch may be old; the physical proof always uses the current held owner.
@MainActor
// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
struct SharedMediaNativeAppPairPlanClosureWitness {
    let preparation: SharedMediaNativeAppPreparationWitness
    let state: SharedMediaNativePairFileState
    let verifyAbsent: () throws -> Void
    fileprivate init(preparation: SharedMediaNativeAppPreparationWitness, state: SharedMediaNativePairFileState,
                     verifyAbsent: @escaping () throws -> Void) {
        self.preparation = preparation; self.state = state; self.verifyAbsent = verifyAbsent
    }
    func validate(_ container: ModelContainer) throws {
        try Task.checkCancellation(); try preparation.validate(container)
        guard try SharedMediaNativeAppPairPlanClosure.state(container, preparation: preparation, plan: state.plan) == state else {
            throw SharedMediaStorageFailure.stale
        }
    }
}

/// Only the fresh delivery method above mints this witness. A decoded plan or
/// completion value grants no app mutation authority.
@MainActor
struct SharedMediaNativeAppPairFileWitness {
    let preparation: SharedMediaNativeAppPreparationWitness
    let state: SharedMediaNativePairFileState
    let binding: SharedMediaNativeBinding
    let action: SharedMediaNativeAppPairAction
    let seal: () throws -> Void
    let beforeReadback: () throws -> Void
    fileprivate init(preparation: SharedMediaNativeAppPreparationWitness, state: SharedMediaNativePairFileState,
                     binding: SharedMediaNativeBinding, action: SharedMediaNativeAppPairAction,
                     seal: @escaping () throws -> Void, beforeReadback: @escaping () throws -> Void) {
        self.preparation = preparation; self.state = state; self.binding = binding
        self.action = action; self.seal = seal; self.beforeReadback = beforeReadback
    }
    func validate(_ container: ModelContainer) throws {
        try Task.checkCancellation(); try preparation.validate(container)
        guard !binding.initializing, state.plan.writerEpoch == binding.epoch,
              preparation.facts.consumers[state.plan.packageID] == nil else { throw SharedMediaStorageFailure.closed }
        let c = ModelContext(container); c.autosaveEnabled = false
        let inventoryID = preparation.authority.profile.inventoryID, packageID = state.plan.packageID
        let inventory = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let package = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        guard try SharedMediaNativePairFileGraph.state(context: c, inventory: inventory, package: package, member: member,
            pairID: state.intent().pairID) == state else { throw SharedMediaStorageFailure.stale }
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory,
            ownerID: preparation.authority.profile.ownerID, format: .appV2)
    }
}

enum SharedMediaNativeAppPairAction {
    case reserve, partial(SharedMediaNativePairPartial), complete(SharedMediaNativePairCompletion), publish([SharedMediaNativePairCompletion])
    var boundaries: (SharedMediaNativePreparationBoundary, SharedMediaNativePreparationBoundary) {
        switch self {
        case .reserve: return (.beforeFileReserve, .afterFileReserve)
        case .partial: return (.beforeFileIdentity, .afterFileIdentity)
        case .complete: return (.beforeFileCompletion, .afterFileCompletion)
        case .publish: return (.beforeFilePublish, .afterFilePublish)
        }
    }
}

/// A saved epoch permits only exact completion/publication of already-bound
/// bytes. It cannot mint fresh reserve/partial authority or accept output data.
@MainActor
struct SharedMediaNativeAppPairRecoveryWitness {
    enum Action {
        case completeSaved(SharedMediaNativePairCompletion), publishSaved([SharedMediaNativePairCompletion])
        var transition: SharedMediaNativeAppPairAction {
            switch self {
            case .completeSaved(let proof): return .complete(proof)
            case .publishSaved(let proofs): return .publish(proofs)
            }
        }
    }
    let preparation: SharedMediaNativeAppPreparationWitness
    let state: SharedMediaNativePairFileState
    let binding: SharedMediaNativeBinding
    let action: Action
    let seal: () throws -> Void
    let beforeReadback: () throws -> Void
    fileprivate init(preparation: SharedMediaNativeAppPreparationWitness, state: SharedMediaNativePairFileState,
                     binding: SharedMediaNativeBinding, action: Action, seal: @escaping () throws -> Void,
                     beforeReadback: @escaping () throws -> Void) {
        self.preparation = preparation; self.state = state; self.binding = binding
        self.action = action; self.seal = seal; self.beforeReadback = beforeReadback
    }
    func validate(_ container: ModelContainer) throws {
        try Task.checkCancellation()
        guard !binding.initializing, state.phase == "writing",
              try Self.currentState(container, preparation: preparation, packageID: state.plan.packageID,
                  pairID: state.intent().pairID) == state else { throw SharedMediaStorageFailure.stale }
        switch action {
        case .completeSaved(let proof):
            guard proof.state == state, try state.selected(proof.workID).0.phase == "writing" else { throw SharedMediaStorageFailure.conflict }
        case .publishSaved(let proofs):
            guard proofs.count == 2, Set(proofs.map(\.workID)) == Set(state.work.map(\.id)),
                  proofs.allSatisfy({ $0.state == state }), state.work.allSatisfy({ $0.phase == "completed" }) else { throw SharedMediaStorageFailure.conflict }
        }
    }
    static func currentState(_ container: ModelContainer, preparation: SharedMediaNativeAppPreparationWitness,
                             packageID: UUID, pairID: UUID) throws -> SharedMediaNativePairFileState {
        try preparation.validate(container)
        guard preparation.action == .inspect, preparation.facts.packages[packageID] != nil,
              preparation.facts.consumers[packageID] == nil else { throw SharedMediaStorageFailure.closed }
        let c = ModelContext(container); c.autosaveEnabled = false
        let inventoryID = preparation.authority.profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let package = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory,
            ownerID: preparation.authority.profile.ownerID, format: .appV2)
        return try SharedMediaNativePairFileGraph.state(context: c, inventory: inventory, package: package, member: member, pairID: pairID)
    }
}

/// App-only sealed retirement authority. No saved state alone grants unlink or
/// release permission, and no retirement action accepts new media bytes.
@MainActor
// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
struct SharedMediaNativeAppPairRetirementWitness {
    enum Action { case retire([SharedMediaNativePairInspection]), inspect, release([SharedMediaNativePairAbsence]) }
    let preparation: SharedMediaNativeAppPreparationWitness
    let state: SharedMediaNativePairFileState
    let binding: SharedMediaNativeBinding
    let action: Action
    let seal: () throws -> Void
    let beforeReadback: () throws -> Void
    fileprivate init(preparation: SharedMediaNativeAppPreparationWitness, state: SharedMediaNativePairFileState,
                     binding: SharedMediaNativeBinding, action: Action, seal: @escaping () throws -> Void,
                     beforeReadback: @escaping () throws -> Void) {
        self.preparation = preparation; self.state = state; self.binding = binding
        self.action = action; self.seal = seal; self.beforeReadback = beforeReadback
    }
    func validate(_ container: ModelContainer) throws {
        try Task.checkCancellation()
        guard !binding.initializing,
              try SharedMediaNativeAppPairRecoveryWitness.currentState(container, preparation: preparation,
                  packageID: state.plan.packageID, pairID: state.intent().pairID) == state,
              case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(state.plan.envelope),
              envelope.attempt == nil, envelope.frozen == nil else { throw SharedMediaStorageFailure.stale }
        switch action {
        case .retire(let proofs):
            guard ["writing", "ready"].contains(state.phase), proofs.count == 2,
                  Set(proofs.map(\.workID)) == Set(state.work.map(\.id)),
                  proofs.allSatisfy({ $0.state == state && $0.binding == binding.bytes && $0.epoch == binding.epoch }) else { throw SharedMediaStorageFailure.conflict }
        case .release(let proofs):
            guard state.phase == "retiring", proofs.count == 2,
                  Set(proofs.map(\.workID)) == Set(state.work.map(\.id)),
                  proofs.allSatisfy({ $0.state == state && $0.binding == binding.bytes && $0.epoch == binding.epoch }) else { throw SharedMediaStorageFailure.conflict }
        case .inspect: guard state.phase == "retiring" else { throw SharedMediaStorageFailure.closed }
        }
    }
}
