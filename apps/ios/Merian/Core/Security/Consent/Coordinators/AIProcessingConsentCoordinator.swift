import Foundation
import Observation

/// Processor choices and beta eligibility; server admission still owns dispatch.
/// ConsentManager retains the required Gemini onboarding and inference gate.
@MainActor
@Observable
final class AIProcessingConsentCoordinator {
    struct Context {
        let observedUserId: UUID?
        let sdkUserId: UUID?
        let isAccountTransitionInProgress: Bool
    }

    private(set) var ownerUserId: UUID?
    private(set) var hasGrantedOpenAI = false
    private(set) var hasOpenAIGrantToWithdraw = false
    private(set) var hasOpenAIHistory = false
    private(set) var hasPendingOpenAIWithdrawal = false
    private(set) var isOpenAIBetaEligible = false
    let isOpenAICollectionEnabled: Bool
    let isOpenAIBetaAccessEnabled: Bool

    var canProcessOpenAI: Bool {
        hasCurrentAccount && (hasGrantedOpenAI || isOpenAIBetaEligible)
    }

    var showsOpenAIChoice: Bool {
        !isOpenAIBetaAccessEnabled && (isOpenAICollectionEnabled || hasOpenAIHistory)
    }

    var hasCurrentAccount: Bool {
        guard let ownerUserId, let context = contextProvider() else { return false }
        return context.observedUserId == ownerUserId
            && context.sdkUserId == ownerUserId
            && !context.isAccountTransitionInProgress
    }

    var canManageOpenAIPermission: Bool {
        hasCurrentAccount && !isOpenAIBetaAccessEnabled
            && (isOpenAICollectionEnabled || hasOpenAIGrantToWithdraw || hasPendingOpenAIWithdrawal)
    }

    @ObservationIgnored private let repository: ConsentLedgerRepository
    @ObservationIgnored private let mutationService: ConsentMutationService
    @ObservationIgnored private var contextProvider: () -> Context? = { nil }
    @ObservationIgnored private var synchronize: () -> Void = {}
    @ObservationIgnored private var failedWithdrawalUserIds: Set<UUID> = []

    init(
        repository: ConsentLedgerRepository,
        mutationService: ConsentMutationService,
        isOpenAICollectionEnabled: Bool = ConsentPolicy.openAIConsentCollectionEnabled,
        isOpenAIBetaAccessEnabled: Bool = ConsentPolicy.openAIBetaAccessEnabled
    ) {
        self.repository = repository
        self.mutationService = mutationService
        self.isOpenAICollectionEnabled = isOpenAICollectionEnabled
        self.isOpenAIBetaAccessEnabled = isOpenAIBetaAccessEnabled
    }

    func setHandlers(
        contextProvider: @escaping () -> Context?,
        synchronize: @escaping () -> Void
    ) {
        self.contextProvider = contextProvider
        self.synchronize = synchronize
    }

    func refresh(ownerUserId: UUID?) {
        self.ownerUserId = ownerUserId
        hasOpenAIHistory = repository.ledger.aiConsentEvents.contains {
            $0.ownerUserId == ownerUserId && $0.provider == ConsentPolicy.openAIProvider
        }
        hasPendingOpenAIWithdrawal = failedWithdrawalUserIds.contains { $0 == ownerUserId }
        let streamHead = ConsentAuthorityPolicy.currentAIConsentStreamHead(
            ownerUserId: ownerUserId, processor: .openAI, in: repository.ledger
        )
        hasOpenAIGrantToWithdraw = streamHead?.eventKind == .granted
        // Beta eligibility is independent of every OpenAI receipt state. The
        // ordinary required-consent gate still owns consent-storage safety.
        isOpenAIBetaEligible = isOpenAIBetaAccessEnabled && ownerUserId != nil
        hasGrantedOpenAI =
            !repository.isLedgerStorageUncertain
            && !hasPendingOpenAIWithdrawal
            && ConsentAuthorityPolicy.currentAIConsentEvent(
                ownerUserId: ownerUserId, processor: .openAI, in: repository.ledger
            )?.eventKind == .granted
    }

    func setOpenAIEnabled(_ enabled: Bool, expectedOwnerUserId: UUID?) throws {
        guard !Task.isCancelled,
            let expectedOwnerUserId, expectedOwnerUserId == ownerUserId,
            hasCurrentAccount
        else {
            throw ConsentHandoffError.activeAccountChanged
        }
        guard !isOpenAIBetaAccessEnabled && (!enabled || isOpenAICollectionEnabled) else {
            throw MerianError.aiConsentRequired
        }
        if !enabled {
            failedWithdrawalUserIds.insert(expectedOwnerUserId)
            refresh(ownerUserId: expectedOwnerUserId)
        }
        // Failed writes publish no grant. A failed withdrawal stays closed in
        // this process and remains retryable; the UI must not report it saved.
        _ = try mutationService.setAIProcessingEnabled(
            enabled, processor: .openAI, ownerUserId: expectedOwnerUserId
        )
        failedWithdrawalUserIds.remove(expectedOwnerUserId)
        refresh(ownerUserId: expectedOwnerUserId)
        synchronize()
    }

    func withdrawGeminiPermission(hasGranted: Bool, ownerUserId: UUID?) throws {
        guard
            try mutationService.withdrawGeminiPermission(
                hasGrantedGeminiProcessing: hasGranted, ownerUserId: ownerUserId
            )
        else { return }
        synchronize()
    }
}
