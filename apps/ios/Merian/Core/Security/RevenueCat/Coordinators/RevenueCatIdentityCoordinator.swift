import Foundation
import Observation

@MainActor
@Observable
final class RevenueCatIdentityCoordinator {
    struct Request: Equatable {
        let appUserID: String
        let authUserID: UUID
        let bindingGeneration: Int64
        let accountKind: String?
        let accountGrantsAllowed: Bool
        let usesStablePurchasePrincipal: Bool
    }

    struct Context: Equatable {
        let request: Request
        let generation: UInt64
        let accountGrantFenceGeneration: UInt64
    }

    typealias LinkOperation = @MainActor (Context) async -> Void

    private(set) var linkedAppUserID: String?
    private(set) var linkedAuthUserID: UUID?
    private(set) var linkedBindingGeneration: Int64?
    private(set) var linkedAccountKind: String?
    private(set) var usesStablePurchasePrincipal = false
    private(set) var accountGrantsAllowed = true
    private(set) var isPurchaseIdentityHandoffPending = false

    private var requestedAppUserID: String?
    private var requestedAuthUserID: UUID?
    private var requestedBindingGeneration: Int64?
    private var requestedAccountKind: String?
    private var requestGeneration: UInt64 = 0
    private var accountGrantFenceGeneration: UInt64 = 0
    @ObservationIgnored private var linkTask: Task<Void, Never>?
    @ObservationIgnored private var linkTaskID: UUID?

    func setPurchaseIdentityHandoffPending(_ pending: Bool) {
        if pending && !isPurchaseIdentityHandoffPending {
            accountGrantFenceGeneration &+= 1
        }
        isPurchaseIdentityHandoffPending = pending
        if pending {
            accountGrantsAllowed = false
        }
    }

    func beginPurchaseIdentityResolution() {
        requestGeneration &+= 1
        requestedAppUserID = nil
        requestedAuthUserID = nil
        requestedBindingGeneration = nil
        requestedAccountKind = nil
        linkedAuthUserID = nil
        linkedBindingGeneration = nil
        linkedAccountKind = nil
        accountGrantsAllowed = false
    }

    func clearProviderIdentityForSignOutIfLegacy() {
        if !usesStablePurchasePrincipal {
            linkedAppUserID = nil
        }
    }

    func link(
        _ request: Request,
        resetPaidReadiness: @MainActor () -> Void,
        operation: @escaping LinkOperation
    ) async {
        let providerIdentityChanged = linkedAppUserID != request.appUserID
        let requiresPaidReadinessReset = RevenueCatIdentityRebindPolicy
            .requiresPaidReadinessReset(
                linkedAppUserID: linkedAppUserID,
                linkedAuthUserID: linkedAuthUserID,
                linkedBindingGeneration: linkedBindingGeneration,
                linkedAccountKind: linkedAccountKind,
                nextAppUserID: request.appUserID,
                nextAuthUserID: request.authUserID,
                nextBindingGeneration: request.bindingGeneration,
                nextAccountKind: request.accountKind
            )

        requestGeneration &+= 1
        let context = Context(
            request: request,
            generation: requestGeneration,
            accountGrantFenceGeneration: accountGrantFenceGeneration
        )
        requestedAppUserID = request.appUserID
        requestedAuthUserID = request.authUserID
        requestedBindingGeneration = request.bindingGeneration
        requestedAccountKind = request.accountKind

        if requiresPaidReadinessReset {
            if providerIdentityChanged {
                linkedAppUserID = nil
            }
            linkedAuthUserID = nil
            linkedBindingGeneration = nil
            linkedAccountKind = nil
            accountGrantsAllowed = false
            resetPaidReadiness()
        }

        let previousTask = linkTask
        let taskID = UUID()
        let task = Task { @MainActor [weak self] in
            defer { self?.finishLinkTask(id: taskID) }
            if let previousTask {
                await previousTask.value
            }
            guard let self, self.isCurrentRequest(context) else { return }
            await operation(context)
        }
        linkTask = task
        linkTaskID = taskID
        await task.value
    }

    func isCurrentRequest(_ context: Context) -> Bool {
        let request = context.request
        return requestGeneration == context.generation
            && requestedAppUserID == request.appUserID
            && requestedAuthUserID == request.authUserID
            && requestedBindingGeneration == request.bindingGeneration
            && requestedAccountKind == request.accountKind
    }

    func commit(_ context: Context) -> Bool {
        guard isCurrentRequest(context) else { return false }
        let request = context.request
        linkedAppUserID = request.appUserID
        linkedAuthUserID = request.authUserID
        linkedBindingGeneration = request.bindingGeneration
        linkedAccountKind = request.accountKind
        usesStablePurchasePrincipal = request.usesStablePurchasePrincipal
        // A handoff may begin while provider work is suspended. Its fence must
        // dominate the older request's captured account-grant permission.
        accountGrantsAllowed = request.accountGrantsAllowed
            && !isPurchaseIdentityHandoffPending
            && context.accountGrantFenceGeneration
                == accountGrantFenceGeneration
        return true
    }

    func isCurrentLinkedIdentity(_ context: Context) -> Bool {
        let request = context.request
        return isCurrentRequest(context)
            && linkedAppUserID == request.appUserID
            && linkedAuthUserID == request.authUserID
            && linkedBindingGeneration == request.bindingGeneration
            && linkedAccountKind == request.accountKind
    }

    func hasCurrentLinkedIdentity(_ appUserID: String) -> Bool {
        requestedAppUserID == appUserID
            && linkedAppUserID == appUserID
            && requestedAuthUserID == linkedAuthUserID
            && requestedBindingGeneration == linkedBindingGeneration
    }

    func isRequestedAppUserID(_ appUserID: String) -> Bool {
        requestedAppUserID == appUserID
    }

    func isProviderMutationIdentityReady(
        providerIdentityReady: Bool
    ) -> Bool {
        RevenueCatAccountMutationPolicy.isReady(
            identityReady: providerIdentityReady,
            requestedAccountKind: requestedAccountKind,
            linkedAccountKind: linkedAccountKind
        )
    }

    func isPurchaseIdentityReady(providerIdentityReady: Bool) -> Bool {
        RevenueCatPurchaseMutationPolicy.isReady(
            providerIdentityReady: isProviderMutationIdentityReady(
                providerIdentityReady: providerIdentityReady
            ),
            identityHandoffPending: isPurchaseIdentityHandoffPending
        )
    }

    private func finishLinkTask(id: UUID) {
        guard linkTaskID == id else { return }
        linkTask = nil
        linkTaskID = nil
    }
}
