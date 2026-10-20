import Foundation
import SwiftData

/// Scoped preparation under one retained app owner. Only a newly acknowledged
/// reservation can enter processing; saved attempts never authorize replay.
@MainActor
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
    private var consumed = false
    private init(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                 expected: SharedMediaNativeAppEligibility.Header, facts: SharedMediaNativeAppMetadataFacts,
                 availableBytes: @escaping () throws -> Int64, boundary: @escaping (SharedMediaNativePreparationBoundary) throws -> Void,
                 io: SharedMediaNativeOriginalIO, focusFactory: ImageFocusWorkFactory,
                 verifyProof: @escaping (SharedMediaPhotoRetirementInspection) throws -> Void) {
        self.container = container; self.authority = authority; self.expected = expected; self.facts = facts
        self.availableBytes = availableBytes; self.boundary = boundary
        self.io = io; self.focusFactory = focusFactory; self.verifyProof = verifyProof
    }
    static func audited(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                        availableBytes: @escaping () throws -> Int64,
                        boundary: @escaping (SharedMediaNativePreparationBoundary) throws -> Void,
                        io: SharedMediaNativeOriginalIO, focusFactory: ImageFocusWorkFactory,
                        verifyProof: @escaping (SharedMediaPhotoRetirementInspection) throws -> Void) async throws -> SharedMediaNativeAppPreparationOperations {
        let expected = try authority.header(container)
        _ = try await SharedMediaNativeScopedAudit(app: container, profile: authority.profile, expected: expected.inventory,
            check: { guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale } },
            betweenPages: { await Task.yield() }).run()
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        return .init(container: container, authority: authority, expected: expected,
            facts: try SharedMediaNativeAppMetadataFacts.capture(context, profile: authority.profile), availableBytes: availableBytes, boundary: boundary,
            io: io, focusFactory: focusFactory, verifyProof: verifyProof)
    }
    private func mutation(_ packageID: UUID, action: SharedMediaNativeAppPreparationWitness.Action) throws -> SharedMediaNativePreparationMutation {
        guard !consumed, facts.packages[packageID] != nil, facts.members[packageID] != nil,
              facts.consumers[packageID] == nil else { throw SharedMediaStorageFailure.closed }
        try boundary(.beforeReadback)
        let witness = SharedMediaNativeAppPreparationWitness(authority: authority, expected: expected, facts: facts, action: action)
        return try .init(container: container, packageID: packageID, witness: witness)
    }
    func reserve(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) throws -> SharedMediaNativePreparationAttempt {
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
        let attempt = try reserve(original: original, recipe: recipe)
        let current = try await Self.audited(container: container, authority: authority, availableBytes: availableBytes,
            boundary: boundary, io: io, focusFactory: focusFactory, verifyProof: verifyProof)
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
        return try mutation.plan(outputs, availableBytes: availableBytes(), beforeSave: { try self.boundary(.beforePairSave) },
            afterSave: { try self.boundary(.afterPairSave) })
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
