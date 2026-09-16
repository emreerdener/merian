import Foundation

/// Owns one Auth session's purchase-principal resolution state and keyed task.
/// Supabase, RevenueCat, entitlement, persistence, and logging effects are
/// supplied by the live composition root.
@MainActor
final class PurchaseIdentitySessionCoordinator {
    private struct ResolutionKey: Equatable {
        let context: PurchaseIdentitySessionContext
        let capabilityFingerprint: String?
        let allowsCapabilityCreation: Bool
    }

    private var resolutionTask: Task<PurchasePrincipalBinding?, Never>?
    private var resolutionTaskID: UUID?
    private var resolutionKey: ResolutionKey?

    private(set) var activeBinding: PurchasePrincipalBinding?
    private(set) var lastLinkedUserID: UUID?

    deinit {
        resolutionTask?.cancel()
    }

    func clearBinding() {
        activeBinding = nil
    }

    func clearLinkedUser() {
        lastLinkedUserID = nil
    }

    func recordBinding(_ binding: PurchasePrincipalBinding) {
        activeBinding = binding
    }

    func recordLinkedUser(_ userID: UUID) {
        lastLinkedUserID = userID
    }

    func cancelResolution() {
        resolutionTask?.cancel()
        resolutionTask = nil
        resolutionTaskID = nil
        resolutionKey = nil
    }

    @discardableResult
    func ensureIdentity(
        for snapshot: PurchaseIdentitySessionSnapshot,
        context: PurchaseIdentitySessionContext,
        expectedCapabilityFingerprint: String? = nil,
        allowsCapabilityCreation: Bool = true,
        isAdmissionCurrent: @MainActor () -> Bool,
        dependencies: PurchaseIdentitySessionDependencies
    ) async -> Bool {
        guard snapshot.matches(context), isAdmissionCurrent() else {
            return false
        }
        do {
            guard try !dependencies.handoff.loadAndPublishPendingState() else {
                dependencies.reportDeferredForHandoff()
                return false
            }
        } catch {
            dependencies.handoff.setPending(true)
            dependencies.reportHandoffStateFailure(error)
            return false
        }

        let providerState = dependencies.provider.currentState()
        let identityChanged = context.userID != lastLinkedUserID
        let accountKindChanged = providerState.linkedAccountKind
            != context.accountKind
        guard expectedCapabilityFingerprint != nil
                || activeBinding == nil
                || identityChanged
                || accountKindChanged
                || !providerState.isIdentityReady else {
            return false
        }

        guard await resolveAndLink(
            snapshot: snapshot,
            context: context,
            expectedCapabilityFingerprint: expectedCapabilityFingerprint,
            allowsCapabilityCreation: allowsCapabilityCreation,
            dependencies: dependencies
        ) != nil else {
            return false
        }
        guard isAdmissionCurrent() else { return false }
        lastLinkedUserID = context.userID
        return identityChanged
    }

    private func resolveAndLink(
        snapshot: PurchaseIdentitySessionSnapshot,
        context: PurchaseIdentitySessionContext,
        expectedCapabilityFingerprint: String?,
        allowsCapabilityCreation: Bool,
        dependencies: PurchaseIdentitySessionDependencies
    ) async -> PurchasePrincipalBinding? {
        let key = ResolutionKey(
            context: context,
            capabilityFingerprint: expectedCapabilityFingerprint,
            allowsCapabilityCreation: allowsCapabilityCreation
        )
        if let resolutionTask, resolutionKey == key {
            return await resolutionTask.value
        }
        cancelResolution()

        let taskID = UUID()
        let task: Task<PurchasePrincipalBinding?, Never> = Task { @MainActor [weak self] in
            guard let self else { return nil }
            return await self.performResolution(
                snapshot: snapshot,
                context: context,
                expectedCapabilityFingerprint:
                    expectedCapabilityFingerprint,
                allowsCapabilityCreation: allowsCapabilityCreation,
                dependencies: dependencies
            )
        }
        resolutionTaskID = taskID
        resolutionKey = key
        resolutionTask = task

        let result = await task.value
        if resolutionTaskID == taskID {
            resolutionTask = nil
            resolutionTaskID = nil
            resolutionKey = nil
        }
        return result
    }

    private func performResolution(
        snapshot: PurchaseIdentitySessionSnapshot,
        context: PurchaseIdentitySessionContext,
        expectedCapabilityFingerprint: String?,
        allowsCapabilityCreation: Bool,
        dependencies: PurchaseIdentitySessionDependencies
    ) async -> PurchasePrincipalBinding? {
        guard dependencies.state.isCurrentPublishedSession(context),
              !Task.isCancelled else {
            return nil
        }

        activeBinding = nil
        dependencies.provider.beginResolution()
        do {
            let binding = try await dependencies.provider.resolve(
                expectedCapabilityFingerprint,
                allowsCapabilityCreation
            )
            guard dependencies.state.isCurrentPublishedSession(context),
                  !Task.isCancelled else {
                return nil
            }
            activeBinding = binding

            switch binding.mode {
            case .stable:
                await dependencies.provider.applyStableBinding(
                    binding,
                    context.userID,
                    context.accountKind
                )
            case .legacy:
                await snapshot.linkLegacyProviderIdentity()
            }

            guard dependencies.state.isCurrentPublishedSession(context),
                  !Task.isCancelled,
                  dependencies.provider.currentState().matches(context) else {
                return nil
            }
            return binding
        } catch {
            dependencies.reportResolutionFailure(error)
            return nil
        }
    }
}
