import Foundation
import SwiftData

/// One already-saved exact send. There is no remote recovery probe or automatic retry.
@MainActor
struct ProtectedInsightChatDeliveryService {
    typealias Store = ProtectedInsightChatPersistence
    typealias Validator = @MainActor @Sendable () throws -> Void
    enum Admission { case initial, explicitReplay(Store.Claim) }
    enum Outcome { case completed(ProtectedInsightChatIntent), held, notStarted }
    let cloud: ObservationHistoryCloudClient
    let submit: (ProtectedInsightChatRequest, UUID, Date, @escaping Validator, @escaping Validator) async throws -> ProtectedInsightChatReply
    var now: () -> Date = Date.init
    var save: (ModelContext) throws -> Void = { try $0.save() }

    static func live(cloud: ObservationHistoryCloudClient, client: MerianNetworkClient) -> Self {
        Self(cloud: cloud, submit: { request, owner, expiry, dispatch, response in
            try await client.sendProtectedInsightChat(request, ownerID: owner, claimExpiresAt: expiry,
                validateAttempt: dispatch, validateResponse: response)
        })
    }

    func deliver(_ intent: ProtectedInsightChatIntent, admission: Admission, container: ModelContainer,
                 isCurrent: @escaping @MainActor @Sendable () -> Bool,
                 permitsDispatch: @escaping @MainActor @Sendable () -> Bool) async throws -> Outcome {
        let saved = try Store.read(intent, container: container, isCurrent: isCurrent)
        if saved.isComplete { return .completed(saved) }
        try Task.checkCancellation()
        guard permitsDispatch() else { return .notStarted }
        let lease = try cloud.begin(intent.ownerID)
        defer { cloud.finish(lease) }
        // Cancellation closes dispatch, not settlement of an answer already received.
        let current: @MainActor @Sendable () -> Bool = {
            isCurrent() && lease.session.userID == intent.ownerID && cloud.isCurrent(lease)
        }
        let claim: Store.Claim?
        switch admission {
        case .initial:
            claim = try Store.claimInitial(saved, at: now(), container: container, isCurrent: current, save: save)
        case .explicitReplay(let previous):
            guard previous.intent.ownerID == saved.ownerID, previous.intent.request == saved.request,
                  previous.intent.requestSHA256 == saved.requestSHA256 else { throw Store.IntegrityError.conflict }
            claim = try Store.claimExplicitReplay(previous, at: now(), container: container, isCurrent: current, save: save)
        }
        guard let claim else { return .notStarted }
        let dispatch: Validator = {
            try Task.checkCancellation()
            guard permitsDispatch() else { throw Store.IntegrityError.unavailable }
            try Store.requireDispatch(claim, at: now(), container: container, isCurrent: current)
        }
        let response: Validator = {
            try Store.requireResponse(claim, container: container, isCurrent: current)
        }
        do {
            try dispatch()
            let reply = try await submit(saved.request, saved.ownerID, claim.expiresAt, dispatch, response)
            try response()
            let completed = try Store.acknowledge(reply.data, claim: claim, at: now(), container: container, isCurrent: current, save: save)
            return .completed(completed)
        } catch {
            // A save may have committed before reporting failure. Never overwrite its exact receipt.
            let recovered = try Store.read(saved, container: container, isCurrent: current)
            if recovered.isComplete { return .completed(recovered) }
            try Store.hold(claim, at: now(), container: container, isCurrent: current, save: save)
            return .held
        }
    }
}
