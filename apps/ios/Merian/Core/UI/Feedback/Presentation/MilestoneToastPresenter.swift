import Foundation
import Observation

@MainActor
@Observable final class MilestoneToastPresenter: MilestoneToastSessionControlling {
    private(set) var presentedItems: [MilestoneToastItem] = []
    private(set) var accountGeneration: UInt64 = 0
    private(set) var sessionGeneration: UInt64 = 0
    private(set) var currentAccountID: String?

    @ObservationIgnored private let maximumPresentedItemCount: Int
    @ObservationIgnored private let automaticDismissInterval: TimeInterval
    @ObservationIgnored private var presentationEffectsClaimed: Set<UUID> = []
    @ObservationIgnored private var presentationStartedAtByID: [UUID: Date] = [:]

    var activeItem: MilestoneToastItem? {
        presentedItems.first
    }

    var queuedItemCount: Int {
        max(presentedItems.count - 1, 0)
    }

    var activeUnlock: MilestoneToastItem? {
        activeItem
    }

    var queuedUnlockCount: Int {
        queuedItemCount
    }

    init(
        maximumPresentedItemCount: Int = 32,
        automaticDismissInterval: TimeInterval = 3.5
    ) {
        self.maximumPresentedItemCount = max(1, maximumPresentedItemCount)
        self.automaticDismissInterval = max(0, automaticDismissInterval)
    }

    var sessionToken: MilestoneToastSessionToken {
        MilestoneToastSessionToken(
            accountGeneration: accountGeneration,
            sessionGeneration: sessionGeneration
        )
    }

    @discardableResult
    func enqueueAchievementUnlock(
        _ award: AwardPayload,
        expectedSession: MilestoneToastSessionToken? = nil
    ) -> MilestoneToastEnqueueOutcome {
        enqueue(
            .achievement(award),
            source: .unlock,
            expectedSession: expectedSession
        )
    }

    @discardableResult
    func enqueueFieldTripProgress(
        _ progress: FieldTripMilestonePayload,
        expectedSession: MilestoneToastSessionToken? = nil
    ) -> MilestoneToastEnqueueOutcome {
        enqueue(
            .fieldTrip(progress),
            source: .unlock,
            expectedSession: expectedSession
        )
    }

    @discardableResult
    func enqueueNewToMerianMilestone(
        expectedSession: MilestoneToastSessionToken? = nil
    ) -> MilestoneToastEnqueueOutcome {
        enqueue(
            .dictionary(.newToMerian),
            source: .unlock,
            expectedSession: expectedSession
        )
    }

    @discardableResult
    func enqueueScanMilestoneBatch(
        fieldTrips: [FieldTripMilestonePayload],
        achievements: [AwardPayload],
        includesNewToMerian: Bool,
        expectedSession: MilestoneToastSessionToken? = nil
    ) -> [MilestoneToastEnqueueOutcome] {
        let payloads = fieldTrips.map(MilestoneToastPayload.fieldTrip)
            + achievements.map(MilestoneToastPayload.achievement)
            + (includesNewToMerian ? [.dictionary(.newToMerian)] : [])

        return payloads.map { payload in
            enqueue(
                payload,
                source: .unlock,
                expectedSession: expectedSession
            )
        }
    }

    #if DEBUG
    func previewAchievementUnlock(_ award: AwardPayload) {
        enqueue(.achievement(award), source: .preview, expectedSession: nil)
    }

    func previewNewToMerianMilestone() {
        enqueue(.dictionary(.newToMerian), source: .preview, expectedSession: nil)
    }

    func previewFieldTripProgress() {
        enqueue(.fieldTrip(.preview), source: .preview, expectedSession: nil)
    }

    func previewMilestoneStack() {
        let achievementType = AchievementType.domesticDog
        let achievement = AwardPayload(
            type: achievementType,
            currentCount: achievementType.definition.targetCount,
            lastInteractionDate: Date()
        )

        clearPresentedItems()
        enqueue(.fieldTrip(.preview), source: .preview, expectedSession: nil)
        enqueue(.achievement(achievement), source: .preview, expectedSession: nil)
        enqueue(.dictionary(.newToMerian), source: .preview, expectedSession: nil)
    }

    func resetForTesting() {
        clearPresentedItems()
        accountGeneration = 0
        sessionGeneration = 0
        currentAccountID = nil
    }
    #endif

    func dismissActiveItem(id: UUID? = nil) {
        guard let activeItem else { return }
        if let id, activeItem.id != id { return }

        let removed = presentedItems.removeFirst()
        clearPresentationMetadata(for: removed.id)
    }

    func dismissActiveUnlock(id: UUID? = nil) {
        dismissActiveItem(id: id)
    }

    func claimPresentationEffects(id: UUID, now: Date) -> Bool {
        guard activeItem?.id == id,
              presentationEffectsClaimed.insert(id).inserted else { return false }
        if presentationStartedAtByID[id] == nil {
            presentationStartedAtByID[id] = now
        }
        return true
    }

    func remainingAutomaticDismissInterval(
        id: UUID,
        now: Date
    ) -> TimeInterval? {
        guard activeItem?.id == id else { return nil }
        let startedAt = presentationStartedAtByID[id] ?? now
        presentationStartedAtByID[id] = startedAt
        return max(automaticDismissInterval - now.timeIntervalSince(startedAt), 0)
    }

    func beginAccountSession(
        accountID: String?,
        origin: AppRouteAccountSessionOrigin,
        now _: Date = Date()
    ) {
        let normalized = MilestoneToastPolicy.normalizedAccountID(accountID)
        guard normalized != currentAccountID else { return }

        if origin == .initialRestoration,
           currentAccountID == nil,
           accountGeneration == 0 {
            currentAccountID = normalized
            return
        }

        currentAccountID = normalized
        accountGeneration &+= 1
        clearPresentedItems()
    }

    func advanceSession(now _: Date = Date()) {
        sessionGeneration &+= 1
        clearPresentedItems()
    }

    @discardableResult
    private func enqueue(
        _ payload: MilestoneToastPayload,
        source: MilestoneToastSource,
        expectedSession: MilestoneToastSessionToken?
    ) -> MilestoneToastEnqueueOutcome {
        if let expectedSession, expectedSession != sessionToken {
            return .rejectedStaleSession
        }

        let newKey = MilestoneToastPolicy.deduplicationKey(for: payload)
        if let existing = presentedItems.first(where: {
            MilestoneToastPolicy.deduplicationKey(for: $0.payload) == newKey
        }) {
            return .coalesced(into: existing.id)
        }

        // Milestones are visual feedback over already-durable domain state. A
        // suspended/backgrounded host must never let this process-local queue
        // grow without bound while completion callbacks continue to arrive.
        guard presentedItems.count < maximumPresentedItemCount else {
            return .droppedOverflow
        }
        let item = MilestoneToastItem(id: UUID(), payload: payload, source: source)
        presentedItems.append(item)
        return .enqueued(item.id)
    }

    private func clearPresentedItems() {
        presentedItems.removeAll(keepingCapacity: false)
        presentationEffectsClaimed.removeAll(keepingCapacity: false)
        presentationStartedAtByID.removeAll(keepingCapacity: false)
    }

    private func clearPresentationMetadata(for id: UUID) {
        presentationEffectsClaimed.remove(id)
        presentationStartedAtByID.removeValue(forKey: id)
    }
}

typealias AchievementToastPresenter = MilestoneToastPresenter
typealias AchievementToastItem = MilestoneToastItem
