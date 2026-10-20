import Foundation
import SwiftData

/// Scoped envelope-only preparation. This owner cannot process, read or write
/// media. Saved attempts are inspectable and explicitly abandonable, never replayed.
@MainActor
final class SharedMediaNativeAppPreparationOperations {
    private let container: ModelContainer
    private let authority: SharedMediaNativeAppOperationAuthority
    private let expected: SharedMediaNativeAppEligibility.Header
    private let facts: SharedMediaNativeAppMetadataFacts
    private let availableBytes: () throws -> Int64
    private let boundary: (SharedMediaNativePreparationBoundary) throws -> Void
    private var consumed = false
    private init(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                 expected: SharedMediaNativeAppEligibility.Header, facts: SharedMediaNativeAppMetadataFacts,
                 availableBytes: @escaping () throws -> Int64, boundary: @escaping (SharedMediaNativePreparationBoundary) throws -> Void) {
        self.container = container; self.authority = authority; self.expected = expected; self.facts = facts
        self.availableBytes = availableBytes; self.boundary = boundary
    }
    static func audited(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                        availableBytes: @escaping () throws -> Int64,
                        boundary: @escaping (SharedMediaNativePreparationBoundary) throws -> Void) async throws -> SharedMediaNativeAppPreparationOperations {
        let expected = try authority.header(container)
        _ = try await SharedMediaNativeScopedAudit(app: container, profile: authority.profile, expected: expected.inventory,
            check: { guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale } },
            betweenPages: { await Task.yield() }).run()
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        return .init(container: container, authority: authority, expected: expected,
            facts: try SharedMediaNativeAppMetadataFacts.capture(context, profile: authority.profile), availableBytes: availableBytes, boundary: boundary)
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
