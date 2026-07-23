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

enum MilestoneToastPayload: Sendable {
    case fieldTrip(FieldTripMilestonePayload)
    case achievement(AwardPayload)
    case dictionary(DictionaryMilestonePayload)
}

struct MilestoneToastItem: Identifiable, Sendable {
    let id: UUID
    let payload: MilestoneToastPayload
    let source: MilestoneToastSource

    var award: AwardPayload? {
        guard case let .achievement(award) = payload else { return nil }
        return award
    }
}

@MainActor
@Observable final class MilestoneToastPresenter {
    static let shared = MilestoneToastPresenter()

    private(set) var presentedItems: [MilestoneToastItem] = []

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

    init() {}

    func enqueueAchievementUnlock(_ award: AwardPayload) {
        enqueue(.achievement(award), source: .unlock)
    }

    func enqueueFieldTripProgress(_ progress: FieldTripMilestonePayload) {
        enqueue(.fieldTrip(progress), source: .unlock)
    }

    func enqueueNewToMerianMilestone() {
        enqueue(.dictionary(.newToMerian), source: .unlock)
    }

    func enqueueScanMilestoneBatch(
        fieldTrips: [FieldTripMilestonePayload],
        achievements: [AwardPayload],
        includesNewToMerian: Bool
    ) {
        let payloads = fieldTrips.map(MilestoneToastPayload.fieldTrip)
            + achievements.map(MilestoneToastPayload.achievement)
            + (includesNewToMerian ? [.dictionary(.newToMerian)] : [])

        for payload in payloads {
            enqueue(payload, source: .unlock)
        }
    }

    #if DEBUG
    func previewAchievementUnlock(_ award: AwardPayload) {
        enqueue(.achievement(award), source: .preview)
    }

    func previewNewToMerianMilestone() {
        enqueue(.dictionary(.newToMerian), source: .preview)
    }

    func previewFieldTripProgress() {
        enqueue(.fieldTrip(.preview), source: .preview)
    }

    func previewMilestoneStack() {
        let achievementType = AchievementType.domesticDog
        let achievement = AwardPayload(
            type: achievementType,
            currentCount: achievementType.definition.targetCount,
            lastInteractionDate: Date()
        )

        presentedItems.removeAll()
        enqueue(.fieldTrip(.preview), source: .preview)
        enqueue(.achievement(achievement), source: .preview)
        enqueue(.dictionary(.newToMerian), source: .preview)
    }

    func resetForTesting() {
        presentedItems.removeAll()
    }
    #endif

    func dismissActiveItem(id: UUID? = nil) {
        guard let activeItem else { return }
        if let id, activeItem.id != id { return }

        presentedItems.removeFirst()
    }

    func dismissActiveUnlock(id: UUID? = nil) {
        dismissActiveItem(id: id)
    }

    private func enqueue(_ payload: MilestoneToastPayload, source: MilestoneToastSource) {
        let item = MilestoneToastItem(id: UUID(), payload: payload, source: source)
        presentedItems.append(item)
    }
}

typealias AchievementToastPresenter = MilestoneToastPresenter
typealias AchievementToastItem = MilestoneToastItem

@MainActor
final class ScanMilestoneCoordinator {
    enum ProgressResolution: Equatable {
        case success(FieldTripProgressResult)
        case retryableFailure
        case terminalFailure
    }

    typealias ProgressResolver = (String, FieldTripPreferredGoal?) async -> ProgressResolution
    typealias AchievementResolver = (ModelContainer?) async -> [AwardPayload]
    typealias FieldTripsAvailabilityResolver = @MainActor () -> Bool
    typealias FieldTripEventsAvailabilityResolver = @MainActor () -> Bool

    static let shared = ScanMilestoneCoordinator()

    private let progressResolver: ProgressResolver
    private let achievementResolver: AchievementResolver
    private let fieldTripsAvailabilityResolver: FieldTripsAvailabilityResolver
    private let fieldTripEventsAvailabilityResolver: FieldTripEventsAvailabilityResolver
    private let presenter: MilestoneToastPresenter
    private var inFlightScanIds: Set<String> = []
    private var completedScanIds: Set<String> = []
    private var completedScanOrder: [String] = []
    private var releasedMilestoneScanIds: Set<String> = []
    private var releasedMilestoneScanOrder: [String] = []
    private var preferredGoalsByScanId: [String: FieldTripPreferredGoal] = [:]
    private var preferredGoalOrder: [String] = []
    private var retryAttemptsByScanId: [String: Int] = [:]
    private var retryTasksByScanId: [String: Task<Void, Never>] = [:]
    private let retryDelays: [Duration]
    private let completedScanLimit = 100

    func registerPreferredGoal(_ preferredGoal: FieldTripPreferredGoal, for scanId: String) {
        preferredGoalsByScanId[scanId] = preferredGoal
        preferredGoalOrder.removeAll(where: { $0 == scanId })
        preferredGoalOrder.append(scanId)
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
        fieldTripEventsAvailabilityResolver: @escaping FieldTripEventsAvailabilityResolver = {
            FieldTripEventsAvailability.isEnabled
        },
        retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15)],
        presenter: MilestoneToastPresenter? = nil
    ) {
        self.progressResolver = progressResolver
        self.achievementResolver = achievementResolver
        self.fieldTripsAvailabilityResolver = fieldTripsAvailabilityResolver
        self.fieldTripEventsAvailabilityResolver = fieldTripEventsAvailabilityResolver
        self.retryDelays = retryDelays
        self.presenter = presenter ?? .shared
    }

    func processCompletedScan(
        scanId: String,
        speciesData: SpeciesData?,
        modelContainer: ModelContainer?,
        preferredGoal: FieldTripPreferredGoal? = nil
    ) async {
        await processCompletedScanAttempt(
            scanId: scanId,
            speciesData: speciesData,
            modelContainer: modelContainer,
            preferredGoal: preferredGoal,
            cancelsScheduledRetry: true
        )
    }

    private func processCompletedScanAttempt(
        scanId: String,
        speciesData: SpeciesData?,
        modelContainer: ModelContainer?,
        preferredGoal: FieldTripPreferredGoal?,
        cancelsScheduledRetry: Bool
    ) async {
        if completedScanIds.contains(scanId) {
            // A prior acknowledgement may have completed while SwiftData was
            // temporarily unavailable. A durable replay can safely finish
            // deleting its outbox hint without re-running milestones.
            OfflineQueueManager.shared.acknowledgeFieldTripProgress(scanId: scanId)
            return
        }
        guard !inFlightScanIds.contains(scanId) else {
            return
        }

        if cancelsScheduledRetry {
            retryTasksByScanId.removeValue(forKey: scanId)?.cancel()
        }

        inFlightScanIds.insert(scanId)
        defer { inFlightScanIds.remove(scanId) }

        let resolvesFieldTrips = fieldTripsAvailabilityResolver()
        let accountId = resolvesFieldTrips
            ? SupabaseManager.shared.currentUser?.id.uuidString
            : nil
        let resolvedPreferredGoal = preferredGoal ?? preferredGoalsByScanId[scanId]
        let progress: FieldTripProgressResult?
        let finalizesFieldTripResolution: Bool

        if resolvesFieldTrips {
            switch await progressResolver(scanId, resolvedPreferredGoal) {
            case .success(let resolvedProgress):
                progress = Self.visibleProgress(
                    resolvedProgress,
                    eventsEnabled: fieldTripEventsAvailabilityResolver()
                )
                finalizesFieldTripResolution = true
                cacheFirstFieldTripAchievement(from: progress, accountId: accountId)
                publishProgressEvents(progress)
                AppEventPublisher.shared.send(
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
                    speciesData: speciesData,
                    modelContainer: modelContainer,
                    preferredGoal: resolvedPreferredGoal
                )
            case .terminalFailure:
                progress = nil
                finalizesFieldTripResolution = true
            }
        } else {
            progress = nil
            finalizesFieldTripResolution = true
        }

        let shouldReleaseOrdinaryMilestones = !releasedMilestoneScanIds.contains(scanId)
        let achievements = (shouldReleaseOrdinaryMilestones
            ? await achievementResolver(modelContainer)
            : []) + newlyUnlockedFirstFieldTripAwards(from: progress)
        let fieldTrips = Self.milestones(from: progress)
        let includesNewToMerian = shouldReleaseOrdinaryMilestones
            && (speciesData.map(Self.isValidNewToMerianMilestone) ?? false)

        presenter.enqueueScanMilestoneBatch(
            fieldTrips: fieldTrips,
            achievements: achievements,
            includesNewToMerian: includesNewToMerian
        )
        if shouldReleaseOrdinaryMilestones {
            rememberReleasedMilestones(scanId)
        }
        if finalizesFieldTripResolution {
            finishFieldTripResolution(scanId: scanId)
        }
    }

    /// Re-applies progress after a user changes a saved scan's identification.
    /// These updates are not part of the original scan-completion milestone batch.
    func processIdentificationUpdate(scanId: String) async {
        guard fieldTripsAvailabilityResolver() else { return }
        let accountId = SupabaseManager.shared.currentUser?.id.uuidString
        guard case .success(let resolvedProgress) = await progressResolver(scanId, nil) else {
            return
        }
        let progress = Self.visibleProgress(
            resolvedProgress,
            eventsEnabled: fieldTripEventsAvailabilityResolver()
        )
        cacheFirstFieldTripAchievement(from: progress, accountId: accountId)
        publishProgressEvents(progress)
        AppEventPublisher.shared.send(.fieldTripScanContributionsInvalidated(scanId: scanId))

        for milestone in Self.milestones(from: progress) {
            presenter.enqueueFieldTripProgress(milestone)
        }
        for award in newlyUnlockedFirstFieldTripAwards(from: progress) {
            presenter.enqueueAchievementUnlock(award)
        }
    }

    static func milestones(from result: FieldTripProgressResult?) -> [FieldTripMilestonePayload] {
        guard let result else { return [] }

        return result.fieldTripUpdates.compactMap(FieldTripMilestonePayload.standard)
            + result.challengeUpdates.compactMap(FieldTripMilestonePayload.challenge)
    }

    static func visibleProgress(
        _ result: FieldTripProgressResult?,
        eventsEnabled: Bool
    ) -> FieldTripProgressResult? {
        guard let result, !eventsEnabled else { return result }

        let achievement = result.firstFieldTripAchievement?.visible(eventsEnabled: false)
        return FieldTripProgressResult(
            fieldTripUpdates: result.fieldTripUpdates,
            challengeUpdates: [],
            firstFieldTripAchievement: achievement,
            firstFieldTripAchievementNewlyUnlocked: achievement == nil
                ? false
                : result.firstFieldTripAchievementNewlyUnlocked
        )
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
    }
    #endif

    private func publishProgressEvents(_ result: FieldTripProgressResult?) {
        guard let result else { return }

        if !result.fieldTripUpdates.isEmpty {
            AppEventPublisher.shared.send(.fieldTripProgressUpdated(result.fieldTripUpdates))
        }
        if !result.challengeUpdates.isEmpty {
            AppEventPublisher.shared.send(.fieldTripChallengeProgressUpdated(result.challengeUpdates))
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
            awards: [award],
            enqueueToasts: false
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

    private func finishFieldTripResolution(scanId: String) {
        retryTasksByScanId.removeValue(forKey: scanId)?.cancel()
        retryAttemptsByScanId.removeValue(forKey: scanId)
        preferredGoalsByScanId.removeValue(forKey: scanId)
        preferredGoalOrder.removeAll(where: { $0 == scanId })
        OfflineQueueManager.shared.acknowledgeFieldTripProgress(scanId: scanId)
        rememberCompletedScan(scanId)
    }

    private func scheduleProgressRetry(
        scanId: String,
        speciesData: SpeciesData?,
        modelContainer: ModelContainer?,
        preferredGoal: FieldTripPreferredGoal?
    ) {
        let attempt = retryAttemptsByScanId[scanId, default: 0]
        guard attempt < retryDelays.count else {
            retryAttemptsByScanId.removeValue(forKey: scanId)
            MerianLog.general.debug(
                "Field trip progress automatic retries exhausted; a later completion callback can retry."
            )
            return
        }

        retryAttemptsByScanId[scanId] = attempt + 1
        retryTasksByScanId.removeValue(forKey: scanId)?.cancel()
        let delay = retryDelays[attempt]
        retryTasksByScanId[scanId] = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }

            while self.inFlightScanIds.contains(scanId) {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
            }
            self.retryTasksByScanId.removeValue(forKey: scanId)
            await self.processCompletedScanAttempt(
                scanId: scanId,
                speciesData: speciesData,
                modelContainer: modelContainer,
                preferredGoal: preferredGoal,
                cancelsScheduledRetry: false
            )
        }
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
            awards: updatedAwards,
            enqueueToasts: false
        )
    }
}
