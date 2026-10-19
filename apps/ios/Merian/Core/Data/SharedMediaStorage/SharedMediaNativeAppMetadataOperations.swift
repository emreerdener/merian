import Foundation
import SwiftData

/// Exact value intent. It cannot authorize a save or change media/lifecycle state.
struct SharedMediaNativeAppMetadataRequest: Sendable {
    let profile: SharedMediaNativeAppProfile
    let header: SharedMediaNativeAppEligibility.Header
    let package: SharedMediaNativeAppMetadataFacts.Package
    let member: SharedMediaNativeAppMetadataFacts.Member
    let envelope: Data
    fileprivate init(profile: SharedMediaNativeAppProfile, header: SharedMediaNativeAppEligibility.Header,
                     package: SharedMediaNativeAppMetadataFacts.Package, member: SharedMediaNativeAppMetadataFacts.Member, envelope: Data) {
        self.profile = profile; self.header = header; self.package = package; self.member = member; self.envelope = envelope
    }
}

/// One operation, one typed save attempt. The private audit witness is never
/// renewed after a save error or lost readback. Exact recovery is read-only;
/// another owner operation must audit again before any future metadata edit.
@MainActor
final class SharedMediaNativeAppMetadataOperations {
    private let container: ModelContainer
    private let authority: SharedMediaNativeAppOperationAuthority
    private let expected: SharedMediaNativeAppEligibility.Header
    private let availableBytes: () throws -> Int64
    private let boundary: (SharedMediaNativeMetadataBoundary) throws -> Void
    private var consumed = false

    private init(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                 expected: SharedMediaNativeAppEligibility.Header, availableBytes: @escaping () throws -> Int64,
                 boundary: @escaping (SharedMediaNativeMetadataBoundary) throws -> Void) {
        self.container = container; self.authority = authority; self.expected = expected
        self.availableBytes = availableBytes; self.boundary = boundary
    }
    static func audited(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                        availableBytes: @escaping () throws -> Int64,
                        boundary: @escaping (SharedMediaNativeMetadataBoundary) throws -> Void) async throws -> Self {
        let expected = try authority.header(container)
        _ = try await SharedMediaNativeScopedAudit(app: container, profile: authority.profile, expected: expected.inventory,
            check: { guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale } },
            betweenPages: { await Task.yield() }).run()
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        return Self(container: container, authority: authority, expected: expected, availableBytes: availableBytes, boundary: boundary)
    }

    func request(packageID: UUID, draftGeneration: UUID, contexts: [ObservationContext],
                 presentation: [PhotoPreparationImagePresentation]?) throws -> SharedMediaNativeAppMetadataRequest {
        try validate()
        let context = fresh(), facts = try SharedMediaNativeAppMetadataFacts.capture(context, profile: authority.profile)
        let package = try target(packageID, context: context)
        guard package.draftGeneration == draftGeneration, let member = facts.members[packageID] else { throw SharedMediaStorageFailure.stale }
        let previous = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData)
        let photos = presentation ?? previous.presentation
        let envelope = try previous.editing(contexts: contexts, presentation: photos)
        try SharedMediaNativeAcquisitionGraph.validatePresentation(photos, package: package, context: context)
        try validate()
        return .init(profile: authority.profile, header: expected, package: .init(package), member: member, envelope: envelope)
    }

    func apply(_ request: SharedMediaNativeAppMetadataRequest) throws -> Int64 {
        try validate()
        guard request.profile == authority.profile else { throw SharedMediaStorageFailure.conflict }
        // Exact already-committed acknowledgement is not a second save attempt.
        if let result = try? readResult(request) { consumed = true; return result }
        guard request.header == expected else { throw SharedMediaStorageFailure.stale }
        let context = fresh(), inventoryID = authority.profile.inventoryID
        let facts = try SharedMediaNativeAppMetadataFacts.capture(context, profile: authority.profile)
        let package = try target(request.package.id, context: context)
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        guard SharedMediaNativeAppMetadataFacts.Package(package) == request.package,
              facts.members[package.id] == request.member else { throw SharedMediaStorageFailure.stale }
        let old = try SharedMediaNativeDraftEnvelope.decode(request.package.envelope)
        try old.validateMetadataTransition(to: request.envelope)
        let next = try SharedMediaNativeDraftEnvelope.decode(request.envelope)
        try SharedMediaNativeAcquisitionGraph.validatePresentation(next.presentation, package: package, context: context)
        let poststate = SharedMediaNativeAppMetadataPoststate(profile: authority.profile, request: request,
            facts: facts, inventoryIdentity: inventory.persistentModelID, packageIdentity: package.persistentModelID)
        package.supportingContextData = request.envelope
        package.revision = try SharedMediaStoragePolicy.add(request.package.revision, 1)
        inventory.revision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateMetadataPoststate(context: context, inventory: inventory, proof: poststate)
        try budget.totals.checkAvailable(availableBytes(), additionalReservation: max(0, Int64(request.envelope.count) - Int64(request.package.envelope.count)))
        try boundary(.beforeSave); try validate(); try poststate.validate(context: context, inventory: inventory)
        guard try SharedMediaNativeAppMetadataFacts.capture(fresh(), profile: authority.profile) == facts else { throw SharedMediaStorageFailure.stale }
        // Consume before calling save: neither a thrown save nor successful
        // read-only recovery can re-enable this operation's write capability.
        consumed = true
        do {
            try context.save()
            try boundary(.afterSave); try boundary(.beforeReadback)
            let result = try readResult(request)
            try facts.validate(fresh(), replacing: request)
            return result
        } catch {
            context.rollback()
            let failure = error
            do {
                try boundary(.beforeReadback)
                let result = try readResult(request)
                try facts.validate(fresh(), replacing: request)
                return result
            } catch { throw failure }
        }
    }

    private func readResult(_ request: SharedMediaNativeAppMetadataRequest) throws -> Int64 {
        let header = try authority.header(container)
        guard request.profile == authority.profile,
              header == (try SharedMediaNativeAppMetadataFacts.successor(request.header)) else { throw SharedMediaStorageFailure.stale }
        let context = fresh(), package = try target(request.package.id, context: context)
        let id = package.id
        let member = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        guard SharedMediaNativeAppMetadataFacts.Package(package) == (try request.package.successor(request.envelope)),
              SharedMediaNativeAppMetadataFacts.Member(member) == request.member else { throw SharedMediaStorageFailure.conflict }
        return package.revision
    }
    private func target(_ id: UUID, context: ModelContext) throws -> PhotoPreparationRecord {
        let package = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
        let member = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        guard package.ownerID == authority.profile.ownerID, package.accountingTierRaw == "pending", package.phaseRaw == "draftOwned",
              !package.retirementRequested, member.inventoryID == authority.profile.inventoryID,
              member.inventoryGeneration == authority.profile.generation, member.ownerID == package.ownerID,
              member.draftGeneration == package.draftGeneration,
              try SharedMediaConsumerLookup.one(context, packageID: id) == nil else { throw SharedMediaStorageFailure.closed }
        let envelope = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData)
        guard envelope.attempt == nil,
              try context.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.packageID == id })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.packageID == id && $0.phaseRaw != "ready" })) == 0 else { throw SharedMediaStorageFailure.closed }
        if case .preparation(let value) = envelope, value.frozen != nil { throw SharedMediaStorageFailure.closed }
        return package
    }
    private func validate() throws {
        guard !consumed, try authority.header(container) == expected else { throw SharedMediaStorageFailure.closed }
    }
    private func fresh() -> ModelContext {
        let context = ModelContext(container); context.autosaveEnabled = false; return context
    }
}

/// Private constructor: only the typed metadata operation can attest its dirty
/// context. This is a bounded projection proof, not a save or file capability.
@MainActor
struct SharedMediaNativeAppMetadataPoststate {
    let profile: SharedMediaNativeAppProfile
    private let request: SharedMediaNativeAppMetadataRequest
    private let facts: SharedMediaNativeAppMetadataFacts
    private let inventoryIdentity: PersistentIdentifier
    private let packageIdentity: PersistentIdentifier
    fileprivate init(profile: SharedMediaNativeAppProfile, request: SharedMediaNativeAppMetadataRequest,
                     facts: SharedMediaNativeAppMetadataFacts, inventoryIdentity: PersistentIdentifier, packageIdentity: PersistentIdentifier) {
        self.profile = profile; self.request = request; self.facts = facts
        self.inventoryIdentity = inventoryIdentity; self.packageIdentity = packageIdentity
    }
    func validate(context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        try SharedMediaNativeAppMetadataFacts.requireWriteSet(context, inventory: inventoryIdentity, package: packageIdentity)
        guard inventory.persistentModelID == inventoryIdentity,
              try SharedMediaNativeAppEligibility.profile(inventory) == profile,
              inventory.revision == (try SharedMediaStoragePolicy.add(request.header.inventory.revision, 1)) else { throw SharedMediaStorageFailure.conflict }
        try facts.validate(context, replacing: request)
    }
    func receivingBytes(_ consumer: SharedMediaConsumerRecord) throws -> Int64 {
        guard facts.consumers[consumer.packageID] == SharedMediaNativeAppMetadataFacts.Consumer(consumer) else { throw SharedMediaStorageFailure.conflict }
        return Int64(consumer.cohortData.count)
    }
}
