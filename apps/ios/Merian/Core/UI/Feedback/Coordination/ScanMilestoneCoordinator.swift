import Foundation
import SwiftData

@MainActor
final class ScanMilestoneCoordinator: MilestoneToastSessionControlling {
    enum ProgressResolution: Equatable {
        case success(FieldTripProgressResult)
        case retryableFailure
        case terminalFailure
    }

    typealias ProgressResolver = (
        String,
        FieldTripPreferredGoal?
    ) async -> ProgressResolution
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
    private let eventSender: any AppEventSending
    private let presenter: MilestoneToastPresenter
    private let dependencies: Dependencies
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

    func registerPreferredGoal(
        _ preferredGoal: FieldTripPreferredGoal,
        for scanId: String
    ) {
        guard let scanKey = Self.scanIdentity(scanId)?.key else { return }
        preferredGoalsByScanId[scanKey] = preferredGoal
        preferredGoalOrder.removeAll(where: { $0 == scanKey })
        preferredGoalOrder.append(scanKey)
        if preferredGoalOrder.count > completedScanLimit {
            preferredGoalsByScanId.removeValue(
                forKey: preferredGoalOrder.removeFirst()
            )
        }
    }

    convenience init(
        progressResolver: @escaping ProgressResolver = ScanMilestoneLiveServices.resolveProgress,
        achievementResolver: @escaping AchievementResolver = ScanMilestoneLiveServices.resolveAchievements,
        fieldTripsAvailabilityResolver: @escaping FieldTripsAvailabilityResolver = ScanMilestoneLiveServices.fieldTripsAvailable,
        retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15)],
        maximumRetryTaskCount: Int = 16,
        presenter: MilestoneToastPresenter,
        dependencies: Dependencies? = nil
    ) {
        self.init(
            progressResolver: progressResolver,
            achievementResolver: achievementResolver,
            fieldTripsAvailabilityResolver: fieldTripsAvailabilityResolver,
            retryDelays: retryDelays,
            maximumRetryTaskCount: maximumRetryTaskCount,
            eventSender: AppEventPublisher(),
            presenter: presenter,
            dependencies: dependencies ?? .live
        )
    }

    init(
        progressResolver: @escaping ProgressResolver = ScanMilestoneLiveServices.resolveProgress,
        achievementResolver: @escaping AchievementResolver = ScanMilestoneLiveServices.resolveAchievements,
        fieldTripsAvailabilityResolver: @escaping FieldTripsAvailabilityResolver = ScanMilestoneLiveServices.fieldTripsAvailable,
        retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15)],
        maximumRetryTaskCount: Int = 16,
        eventSender: any AppEventSending,
        presenter: MilestoneToastPresenter,
        dependencies: Dependencies? = nil
    ) {
        self.progressResolver = progressResolver
        self.achievementResolver = achievementResolver
        self.fieldTripsAvailabilityResolver = fieldTripsAvailabilityResolver
        self.retryDelays = retryDelays
        self.maximumRetryTaskCount = max(1, maximumRetryTaskCount)
        self.eventSender = eventSender
        self.presenter = presenter
        self.dependencies = dependencies ?? .live
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
        let sessionScanKey = SessionScanKey(
            session: expectedSession,
            scanKey: scanKey
        )
        if completedScanIds.contains(scanKey) {
            // A prior acknowledgement may have completed while SwiftData was
            // temporarily unavailable. A durable replay can safely finish
            // deleting its outbox hint without re-running milestones.
            dependencies.acknowledgeFieldTripProgress(scanId)
            return
        }
        guard !inFlightScanIds.contains(sessionScanKey) else { return }

        if cancelsScheduledRetry {
            retryTasksByScanId.removeValue(forKey: scanKey)?.cancel()
            retryTaskOrder.removeAll(where: { $0 == scanKey })
        }

        inFlightScanIds.insert(sessionScanKey)
        defer { inFlightScanIds.remove(sessionScanKey) }

        let resolvesFieldTrips = fieldTripsAvailabilityResolver()
        let accountId = resolvesFieldTrips ? dependencies.currentAccountID() : nil
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
                cacheFirstFieldTripAchievement(
                    from: progress,
                    accountId: accountId
                )
                publishProgressEvents(progress)
                eventSender.send(
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

        let shouldReleaseOrdinaryMilestones = !releasedMilestoneScanIds.contains(
            scanKey
        )
        let ordinaryAchievements: [AwardPayload]
        if shouldReleaseOrdinaryMilestones {
            ordinaryAchievements = await achievementResolver(modelContainer)
            guard expectedSession == presenter.sessionToken else { return }
        } else {
            ordinaryAchievements = []
        }
        let achievements = ordinaryAchievements
            + newlyUnlockedFirstFieldTripAwards(from: progress)
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
        let accountId = dependencies.currentAccountID()
        guard case .success(let resolvedProgress) = await progressResolver(
            scanId,
            nil
        ) else {
            return
        }
        guard expectedSession == presenter.sessionToken else { return }
        let progress = resolvedProgress
        cacheFirstFieldTripAchievement(from: progress, accountId: accountId)
        publishProgressEvents(progress)
        eventSender.send(.fieldTripScanContributionsInvalidated(scanId: scanId))

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

    static func milestones(
        from result: FieldTripProgressResult?
    ) -> [FieldTripMilestonePayload] {
        ScanMilestonePolicy.milestones(from: result)
    }

    static func isValidNewToMerianMilestone(_ data: SpeciesData) -> Bool {
        ScanMilestonePolicy.isValidNewToMerianMilestone(data)
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
            eventSender.send(
                .fieldTripProgressInvalidated(
                    templateIds: Set(result.fieldTripUpdates.map(\.templateId))
                )
            )
        }
        if !result.challengeUpdates.isEmpty {
            eventSender.send(
                .fieldTripChallengeProgressInvalidated(
                    challengeIds: Set(
                        result.challengeUpdates.map(\.challengeId)
                    )
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
              dependencies.currentAccountID() == accountId else { return }
        dependencies.saveFirstFieldTripAchievement(progress, accountId)
    }

    private func newlyUnlockedFirstFieldTripAwards(
        from result: FieldTripProgressResult?
    ) -> [AwardPayload] {
        guard result?.firstFieldTripAchievementNewlyUnlocked == true,
              let award = result?.firstFieldTripAchievement?.awardPayload else {
            return []
        }
        return dependencies.evaluateAchievementsForNotifications([award])
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
        dependencies.acknowledgeFieldTripProgress(scanId)
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

            let sessionScanKey = SessionScanKey(
                session: expectedSession,
                scanKey: scanKey
            )
            while self.inFlightScanIds.contains(sessionScanKey) {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled,
                      expectedSession == self.presenter.sessionToken else {
                    return
                }
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

    private static func scanIdentity(
        _ scanId: String
    ) -> ScanMilestoneIdentity? {
        ScanMilestonePolicy.identity(for: scanId)
    }
}
