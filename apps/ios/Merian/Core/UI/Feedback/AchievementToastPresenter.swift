import Foundation
import Observation
import SwiftData

enum MilestoneToastSource: Sendable, Equatable {
    case unlock
    case preview
}

struct DictionaryMilestonePayload: Sendable, Equatable {
    let title: String
    let subtitle: String
    let imageName: String

    static let newToMerian = DictionaryMilestonePayload(
        title: "New to Naturebook",
        subtitle: "Added to the species dictionary",
        imageName: "star"
    )
}

struct FieldTripMilestonePayload: Sendable, Equatable {
    let tripTitle: String
    let goalLabel: String
    let artwork: CaptureGoalArtwork
    let destination: CaptureGoalDestination

    var title: String {
        goalLabel.isEmpty ? "Goal complete" : "\(goalLabel) goal complete"
    }

    static func standard(update: FieldTripProgressUpdate) -> FieldTripMilestonePayload? {
        guard let item = update.newlyCompletedItems.first else { return nil }

        return FieldTripMilestonePayload(
            tripTitle: update.title,
            goalLabel: item.toastGoalLabel,
            artwork: toastArtwork(for: item, templateSlug: update.slug),
            destination: .fieldTrip(
                templateId: update.templateId,
                checklistItemId: item.itemId
            )
        )
    }

    static func challenge(update: FieldTripChallengeProgressUpdate) -> FieldTripMilestonePayload? {
        guard let item = update.newlyCompletedItems.first else { return nil }

        return FieldTripMilestonePayload(
            tripTitle: update.title,
            goalLabel: item.toastGoalLabel,
            artwork: toastArtwork(for: item, templateSlug: update.slug),
            destination: .fieldTripChallenge(challengeId: update.challengeId)
        )
    }

    private static func toastArtwork(
        for item: FieldTripProgressCompletedItem,
        templateSlug: String
    ) -> CaptureGoalArtwork {
        guard let imageName = FieldTripObjectiveArtwork.exactImageName(
            for: item.prompt,
            templateSlug: templateSlug
        ) else {
            return .systemSymbol(name: "binoculars.fill")
        }

        return .bundledImage(name: imageName)
    }

    #if DEBUG
    static let preview = FieldTripMilestonePayload(
        tripTitle: "Backyard Safari",
        goalLabel: "Spider",
        artwork: .bundledImage(name: "fieldtrip-backyard-spider"),
        destination: .fieldTrip(templateId: "preview", checklistItemId: "preview")
    )
    #endif
}

private extension FieldTripProgressCompletedItem {
    var toastGoalLabel: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum MilestoneToastPayload: Sendable, Equatable {
    case fieldTrip(FieldTripMilestonePayload)
    case achievement(AwardPayload)
    case dictionary(DictionaryMilestonePayload)
}

struct MilestoneToastItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let payload: MilestoneToastPayload
    let source: MilestoneToastSource

    var award: AwardPayload? {
        guard case let .achievement(award) = payload else { return nil }
        return award
    }
}

enum MilestoneToastDeduplicationKey: Sendable, Equatable {
    case fieldTrip(destination: CaptureGoalDestination, goalLabel: String)
    case achievement(AchievementType)
    case dictionary(title: String)
}

enum MilestoneToastEnqueueOutcome: Sendable, Equatable {
    case enqueued(UUID)
    case coalesced(into: UUID)
    case droppedOverflow
    case rejectedStaleSession
}

struct MilestoneToastSessionToken: Sendable, Equatable {
    let accountGeneration: UInt64
    let sessionGeneration: UInt64
}

protocol MilestoneToastClock: Sendable {
    func now() -> Date
    func sleep(for interval: TimeInterval) async throws
}

struct ContinuousMilestoneToastClock: MilestoneToastClock {
    func now() -> Date {
        Date()
    }

    func sleep(for interval: TimeInterval) async throws {
        let nanoseconds = UInt64(max(interval, 0) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

@MainActor
protocol MilestoneToastSessionControlling: AnyObject {
    func beginAccountSession(
        accountID: String?,
        origin: AppRouteAccountSessionOrigin,
        now: Date
    )
    func advanceSession(now: Date)
}

/// Tracks nested visual hosts without retaining views. The most recently
/// mounted host owns presentation; removing it restores the previous host.
@MainActor
@Observable final class MilestoneToastHostRegistry {
    private(set) var hostIDs: [UUID] = []
    @ObservationIgnored private let maximumHostCount: Int

    init(maximumHostCount: Int = 8) {
        self.maximumHostCount = max(1, maximumHostCount)
    }

    var activeHostID: UUID? {
        hostIDs.last
    }

    func register(_ hostID: UUID) {
        guard activeHostID != hostID else { return }
        hostIDs.removeAll(where: { $0 == hostID })
        hostIDs.append(hostID)
        if hostIDs.count > maximumHostCount {
            hostIDs.removeFirst(hostIDs.count - maximumHostCount)
        }
    }

    func unregister(_ hostID: UUID) {
        hostIDs.removeAll(where: { $0 == hostID })
    }
}

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

    func remainingAutomaticDismissInterval(id: UUID, now: Date) -> TimeInterval? {
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
        let trimmedAccountID = accountID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmedAccountID.flatMap { $0.isEmpty ? nil : $0.lowercased() }
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

        let newDeduplicationKey = deduplicationKey(for: payload)
        if let existing = presentedItems.first(where: {
            deduplicationKey(for: $0.payload) == newDeduplicationKey
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

    private func deduplicationKey(
        for payload: MilestoneToastPayload
    ) -> MilestoneToastDeduplicationKey {
        switch payload {
        case .fieldTrip(let progress):
            .fieldTrip(destination: progress.destination, goalLabel: progress.goalLabel)
        case .achievement(let award):
            .achievement(award.type)
        case .dictionary(let milestone):
            .dictionary(title: milestone.title)
        }
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

@MainActor
final class ScanMilestoneCoordinator: MilestoneToastSessionControlling {
    enum ProgressResolution: Equatable {
        case success(FieldTripProgressResult)
        case retryableFailure
        case terminalFailure
    }

    typealias ProgressResolver = (String, FieldTripPreferredGoal?) async -> ProgressResolution
    typealias AchievementResolver = (ModelContainer?) async -> [AwardPayload]
    typealias FieldTripsAvailabilityResolver = @MainActor () -> Bool

    private struct SessionScanKey: Hashable {
        let accountGeneration: UInt64
        let sessionGeneration: UInt64
        let scanKey: String

        init(session: MilestoneToastSessionToken, scanKey: String) {
            accountGeneration = session.accountGeneration
            sessionGeneration = session.sessionGeneration
            self.scanKey = scanKey
        }
    }

    private let progressResolver: ProgressResolver
    private let achievementResolver: AchievementResolver
    private let fieldTripsAvailabilityResolver: FieldTripsAvailabilityResolver
    private let presenter: MilestoneToastPresenter
    private var inFlightScanIds: Set<SessionScanKey> = []
    private var completedScanIds: Set<String> = []
    private var completedScanOrder: [String] = []
    private var releasedMilestoneScanIds: Set<String> = []
    private var releasedMilestoneScanOrder: [String] = []
    private var preferredGoalsByScanId: [String: FieldTripPreferredGoal] = [:]
    private var preferredGoalOrder: [String] = []
    private var retryAttemptsByScanId: [String: Int] = [:]
    private var retryTasksByScanId: [String: Task<Void, Never>] = [:]
    private var retryTaskOrder: [String] = []
    private let retryDelays: [Duration]
    private let maximumRetryTaskCount: Int
    private let completedScanLimit = 100

    func registerPreferredGoal(_ preferredGoal: FieldTripPreferredGoal, for scanId: String) {
        guard let scanKey = Self.scanIdentity(scanId)?.key else { return }
        preferredGoalsByScanId[scanKey] = preferredGoal
        preferredGoalOrder.removeAll(where: { $0 == scanKey })
        preferredGoalOrder.append(scanKey)
        if preferredGoalOrder.count > completedScanLimit {
            preferredGoalsByScanId.removeValue(forKey: preferredGoalOrder.removeFirst())
        }
    }

    init(
        progressResolver: @escaping ProgressResolver = ScanMilestoneCoordinator.resolveProgress,
        achievementResolver: @escaping AchievementResolver = ScanMilestoneCoordinator.resolveAchievements,
        fieldTripsAvailabilityResolver: @escaping FieldTripsAvailabilityResolver = {
            FeatureFlags.isEnabled(.fieldTrips)
        },
        retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15)],
        maximumRetryTaskCount: Int = 16,
        presenter: MilestoneToastPresenter
    ) {
        self.progressResolver = progressResolver
        self.achievementResolver = achievementResolver
        self.fieldTripsAvailabilityResolver = fieldTripsAvailabilityResolver
        self.retryDelays = retryDelays
        self.maximumRetryTaskCount = max(1, maximumRetryTaskCount)
        self.presenter = presenter
    }

    func beginAccountSession(
        accountID: String?,
        origin: AppRouteAccountSessionOrigin,
        now: Date
    ) {
        let previousSession = presenter.sessionToken
        presenter.beginAccountSession(accountID: accountID, origin: origin, now: now)
        guard presenter.sessionToken != previousSession else { return }
        cancelSessionBoundWork(resetsScanHistory: true)
    }

    func advanceSession(now: Date) {
        presenter.advanceSession(now: now)
        cancelSessionBoundWork(resetsScanHistory: false)
    }

    func processCompletedScan(
        scanId: String,
        speciesData: SpeciesData?,
        modelContainer: ModelContainer?,
        preferredGoal: FieldTripPreferredGoal? = nil
    ) async {
        guard let identity = Self.scanIdentity(scanId) else { return }
        let expectedSession = presenter.sessionToken
        await processCompletedScanAttempt(
            scanId: identity.value,
            scanKey: identity.key,
            speciesData: speciesData,
            modelContainer: modelContainer,
            preferredGoal: preferredGoal,
            cancelsScheduledRetry: true,
            expectedSession: expectedSession
        )
    }

    private func processCompletedScanAttempt(
        scanId: String,
        scanKey: String,
        speciesData: SpeciesData?,
        modelContainer: ModelContainer?,
        preferredGoal: FieldTripPreferredGoal?,
        cancelsScheduledRetry: Bool,
        expectedSession: MilestoneToastSessionToken
    ) async {
        guard expectedSession == presenter.sessionToken else { return }
        let sessionScanKey = SessionScanKey(session: expectedSession, scanKey: scanKey)
        if completedScanIds.contains(scanKey) {
            // A prior acknowledgement may have completed while SwiftData was
            // temporarily unavailable. A durable replay can safely finish
            // deleting its outbox hint without re-running milestones.
            OfflineQueueManager.shared.acknowledgeFieldTripProgress(scanId: scanId)
            return
        }
        guard !inFlightScanIds.contains(sessionScanKey) else {
            return
        }

        if cancelsScheduledRetry {
            retryTasksByScanId.removeValue(forKey: scanKey)?.cancel()
            retryTaskOrder.removeAll(where: { $0 == scanKey })
        }

        inFlightScanIds.insert(sessionScanKey)
        defer { inFlightScanIds.remove(sessionScanKey) }

        let resolvesFieldTrips = fieldTripsAvailabilityResolver()
        let accountId = resolvesFieldTrips
            ? SupabaseManager.shared.currentUser?.id.uuidString
            : nil
        let resolvedPreferredGoal = preferredGoal ?? preferredGoalsByScanId[scanKey]
        let progress: FieldTripProgressResult?
        let finalizesFieldTripResolution: Bool

        if resolvesFieldTrips {
            let resolution = await progressResolver(scanId, resolvedPreferredGoal)
            guard expectedSession == presenter.sessionToken else { return }

            switch resolution {
            case .success(let resolvedProgress):
                progress = resolvedProgress
                finalizesFieldTripResolution = true
                cacheFirstFieldTripAchievement(from: progress, accountId: accountId)
                publishProgressEvents(progress)
                AppDIContainer.shared.appEventPublisher.send(
                    .fieldTripScanContributionsInvalidated(scanId: scanId)
                )
            case .retryableFailure:
                progress = nil
                finalizesFieldTripResolution = false
                if let resolvedPreferredGoal {
                    registerPreferredGoal(resolvedPreferredGoal, for: scanId)
                }
                scheduleProgressRetry(
                    scanId: scanId,
                    scanKey: scanKey,
                    speciesData: speciesData,
                    modelContainer: modelContainer,
                    preferredGoal: resolvedPreferredGoal,
                    expectedSession: expectedSession
                )
            case .terminalFailure:
                progress = nil
                finalizesFieldTripResolution = true
            }
        } else {
            progress = nil
            finalizesFieldTripResolution = true
        }

        let shouldReleaseOrdinaryMilestones = !releasedMilestoneScanIds.contains(scanKey)
        let ordinaryAchievements: [AwardPayload]
        if shouldReleaseOrdinaryMilestones {
            ordinaryAchievements = await achievementResolver(modelContainer)
            guard expectedSession == presenter.sessionToken else { return }
        } else {
            ordinaryAchievements = []
        }
        let achievements = ordinaryAchievements + newlyUnlockedFirstFieldTripAwards(from: progress)
        let fieldTrips = Self.milestones(from: progress)
        let includesNewToMerian = shouldReleaseOrdinaryMilestones
            && (speciesData.map(Self.isValidNewToMerianMilestone) ?? false)

        presenter.enqueueScanMilestoneBatch(
            fieldTrips: fieldTrips,
            achievements: achievements,
            includesNewToMerian: includesNewToMerian,
            expectedSession: expectedSession
        )
        if shouldReleaseOrdinaryMilestones {
            rememberReleasedMilestones(scanKey)
        }
        if finalizesFieldTripResolution {
            finishFieldTripResolution(scanId: scanId, scanKey: scanKey)
        }
    }

    /// Re-applies progress after a user changes a saved scan's identification.
    /// These updates are not part of the original scan-completion milestone batch.
    func processIdentificationUpdate(scanId: String) async {
        guard let scanId = Self.scanIdentity(scanId)?.value else { return }
        let expectedSession = presenter.sessionToken
        guard fieldTripsAvailabilityResolver() else { return }
        let accountId = SupabaseManager.shared.currentUser?.id.uuidString
        guard case .success(let resolvedProgress) = await progressResolver(scanId, nil) else {
            return
        }
        guard expectedSession == presenter.sessionToken else { return }
        let progress = resolvedProgress
        cacheFirstFieldTripAchievement(from: progress, accountId: accountId)
        publishProgressEvents(progress)
        AppDIContainer.shared.appEventPublisher.send(.fieldTripScanContributionsInvalidated(scanId: scanId))

        for milestone in Self.milestones(from: progress) {
            presenter.enqueueFieldTripProgress(
                milestone,
                expectedSession: expectedSession
            )
        }
        for award in newlyUnlockedFirstFieldTripAwards(from: progress) {
            presenter.enqueueAchievementUnlock(
                award,
                expectedSession: expectedSession
            )
        }
    }

    static func milestones(from result: FieldTripProgressResult?) -> [FieldTripMilestonePayload] {
        guard let result else { return [] }

        return result.fieldTripUpdates.compactMap(FieldTripMilestonePayload.standard)
            + result.challengeUpdates.compactMap(FieldTripMilestonePayload.challenge)
    }

    static func isValidNewToMerianMilestone(_ data: SpeciesData) -> Bool {
        let lowerName = data.commonName.lowercased()
        return data.isNewToMerianDictionary
            && data.isBiological
            && lowerName != "not applicable"
            && lowerName != "unknown subject"
            && lowerName != "inanimate object"
    }

    #if DEBUG
    func resetForTesting() {
        for task in retryTasksByScanId.values {
            task.cancel()
        }
        inFlightScanIds.removeAll()
        completedScanIds.removeAll()
        completedScanOrder.removeAll()
        releasedMilestoneScanIds.removeAll()
        releasedMilestoneScanOrder.removeAll()
        preferredGoalsByScanId.removeAll()
        preferredGoalOrder.removeAll()
        retryAttemptsByScanId.removeAll()
        retryTasksByScanId.removeAll()
        retryTaskOrder.removeAll()
    }

    var pendingRetryTaskCountForTesting: Int {
        retryTasksByScanId.count
    }
    #endif

    private func publishProgressEvents(_ result: FieldTripProgressResult?) {
        guard let result else { return }

        if !result.fieldTripUpdates.isEmpty {
            AppDIContainer.shared.appEventPublisher.send(
                .fieldTripProgressInvalidated(
                    templateIds: Set(result.fieldTripUpdates.map(\.templateId))
                )
            )
        }
        if !result.challengeUpdates.isEmpty {
            AppDIContainer.shared.appEventPublisher.send(
                .fieldTripChallengeProgressInvalidated(
                    challengeIds: Set(result.challengeUpdates.map(\.challengeId))
                )
            )
        }
    }

    private func cacheFirstFieldTripAchievement(
        from result: FieldTripProgressResult?,
        accountId: String?
    ) {
        guard let progress = result?.firstFieldTripAchievement,
              let accountId,
              SupabaseManager.shared.currentUser?.id.uuidString == accountId else { return }
        FirstFieldTripAchievementProgressStore.save(progress, accountId: accountId)
    }

    private func newlyUnlockedFirstFieldTripAwards(
        from result: FieldTripProgressResult?
    ) -> [AwardPayload] {
        guard result?.firstFieldTripAchievementNewlyUnlocked == true,
              let award = result?.firstFieldTripAchievement?.awardPayload else { return [] }
        return GamificationManager.shared.evaluateAchievementsForNotifications(
            awards: [award]
        )
    }

    private func rememberCompletedScan(_ scanId: String) {
        completedScanIds.insert(scanId)
        completedScanOrder.append(scanId)

        if completedScanOrder.count > completedScanLimit {
            let expiredScanId = completedScanOrder.removeFirst()
            completedScanIds.remove(expiredScanId)
        }
    }

    private func rememberReleasedMilestones(_ scanId: String) {
        releasedMilestoneScanIds.insert(scanId)
        releasedMilestoneScanOrder.append(scanId)

        if releasedMilestoneScanOrder.count > completedScanLimit {
            let expiredScanId = releasedMilestoneScanOrder.removeFirst()
            releasedMilestoneScanIds.remove(expiredScanId)
        }
    }

    private func finishFieldTripResolution(scanId: String, scanKey: String) {
        retryTasksByScanId.removeValue(forKey: scanKey)?.cancel()
        retryTaskOrder.removeAll(where: { $0 == scanKey })
        retryAttemptsByScanId.removeValue(forKey: scanKey)
        preferredGoalsByScanId.removeValue(forKey: scanKey)
        preferredGoalOrder.removeAll(where: { $0 == scanKey })
        OfflineQueueManager.shared.acknowledgeFieldTripProgress(scanId: scanId)
        rememberCompletedScan(scanKey)
    }

    private func scheduleProgressRetry(
        scanId: String,
        scanKey: String,
        speciesData: SpeciesData?,
        modelContainer: ModelContainer?,
        preferredGoal: FieldTripPreferredGoal?,
        expectedSession: MilestoneToastSessionToken
    ) {
        guard expectedSession == presenter.sessionToken else { return }
        let attempt = retryAttemptsByScanId[scanKey, default: 0]
        guard attempt < retryDelays.count else {
            retryAttemptsByScanId.removeValue(forKey: scanKey)
            MerianLog.general.debug(
                "Field trip progress automatic retries exhausted; a later completion callback can retry."
            )
            return
        }

        retryAttemptsByScanId[scanKey] = attempt + 1
        retryTasksByScanId.removeValue(forKey: scanKey)?.cancel()
        retryTaskOrder.removeAll(where: { $0 == scanKey })
        makeRetryTaskCapacity()
        let delay = retryDelays[attempt]
        retryTaskOrder.append(scanKey)
        retryTasksByScanId[scanKey] = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  expectedSession == self.presenter.sessionToken else { return }

            let sessionScanKey = SessionScanKey(session: expectedSession, scanKey: scanKey)
            while self.inFlightScanIds.contains(sessionScanKey) {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled,
                      expectedSession == self.presenter.sessionToken else { return }
            }
            self.retryTasksByScanId.removeValue(forKey: scanKey)
            self.retryTaskOrder.removeAll(where: { $0 == scanKey })
            await self.processCompletedScanAttempt(
                scanId: scanId,
                scanKey: scanKey,
                speciesData: speciesData,
                modelContainer: modelContainer,
                preferredGoal: preferredGoal,
                cancelsScheduledRetry: false,
                expectedSession: expectedSession
            )
        }
    }

    private func makeRetryTaskCapacity() {
        while retryTasksByScanId.count >= maximumRetryTaskCount,
              let evictedScanKey = retryTaskOrder.first {
            retryTaskOrder.removeFirst()
            retryTasksByScanId.removeValue(forKey: evictedScanKey)?.cancel()
            retryAttemptsByScanId.removeValue(forKey: evictedScanKey)
            preferredGoalsByScanId.removeValue(forKey: evictedScanKey)
            preferredGoalOrder.removeAll(where: { $0 == evictedScanKey })
        }
    }

    private func cancelSessionBoundWork(resetsScanHistory: Bool) {
        for task in retryTasksByScanId.values {
            task.cancel()
        }
        retryTasksByScanId.removeAll(keepingCapacity: false)
        retryTaskOrder.removeAll(keepingCapacity: false)
        retryAttemptsByScanId.removeAll(keepingCapacity: false)
        preferredGoalsByScanId.removeAll(keepingCapacity: false)
        preferredGoalOrder.removeAll(keepingCapacity: false)
        inFlightScanIds.removeAll(keepingCapacity: false)
        guard resetsScanHistory else { return }
        completedScanIds.removeAll(keepingCapacity: false)
        completedScanOrder.removeAll(keepingCapacity: false)
        releasedMilestoneScanIds.removeAll(keepingCapacity: false)
        releasedMilestoneScanOrder.removeAll(keepingCapacity: false)
    }

    private static func scanIdentity(_ scanId: String) -> (value: String, key: String)? {
        let value = scanId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return (value, value.lowercased())
    }

    private static func resolveProgress(
        scanId: String,
        preferredGoal: FieldTripPreferredGoal?
    ) async -> ProgressResolution {
        do {
            var isPersisted = false
            let retryDelaysMilliseconds = [0, 250, 500, 1_000, 2_000, 4_000]
            for delay in retryDelaysMilliseconds {
                if delay > 0 {
                    try await Task.sleep(for: .milliseconds(delay))
                }
                try Task.checkCancellation()
                let status = try await MerianNetworkClient.shared.checkScanStatusDetails(scanId: scanId)
                if status.isFound {
                    isPersisted = true
                    break
                }
                if status.jobStatus == .failed { return .terminalFailure }
            }
            guard isPersisted else {
                MerianLog.general.debug(
                    "Field trip progress deferred because remote scan persistence is not complete."
                )
                return .retryableFailure
            }

            return .success(
                try await MerianNetworkClient.shared.applyFieldTripProgress(
                    scanId: scanId,
                    preferredGoal: preferredGoal
                )
            )
        } catch is CancellationError {
            return .retryableFailure
        } catch {
            MerianLog.general.debug("Field trip progress update failed: \(error, privacy: .private)")
            return .retryableFailure
        }
    }

    private static func resolveAchievements(modelContainer: ModelContainer?) async -> [AwardPayload] {
        guard let modelContainer else { return [] }

        let profileActor = OfflineQueueManager.shared.resolvedProfileDbActor(container: modelContainer)
        let updatedAwards = await profileActor.calculateAwards()
        return GamificationManager.shared.evaluateAchievementsForNotifications(
            awards: updatedAwards
        )
    }
}
