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
    typealias ProgressResolver = (String) async -> FieldTripProgressResult?
    typealias AchievementResolver = (ModelContainer?) async -> [AwardPayload]

    static let shared = ScanMilestoneCoordinator()

    private let progressResolver: ProgressResolver
    private let achievementResolver: AchievementResolver
    private let presenter: MilestoneToastPresenter
    private var inFlightScanIds: Set<String> = []
    private var completedScanIds: Set<String> = []
    private var completedScanOrder: [String] = []
    private let completedScanLimit = 100

    init(
        progressResolver: @escaping ProgressResolver = ScanMilestoneCoordinator.resolveProgress,
        achievementResolver: @escaping AchievementResolver = ScanMilestoneCoordinator.resolveAchievements,
        presenter: MilestoneToastPresenter? = nil
    ) {
        self.progressResolver = progressResolver
        self.achievementResolver = achievementResolver
        self.presenter = presenter ?? .shared
    }

    func processCompletedScan(
        scanId: String,
        speciesData: SpeciesData?,
        modelContainer: ModelContainer?
    ) async {
        guard !inFlightScanIds.contains(scanId), !completedScanIds.contains(scanId) else {
            return
        }

        inFlightScanIds.insert(scanId)
        defer { inFlightScanIds.remove(scanId) }

        let progress = await progressResolver(scanId)
        publishProgressEvents(progress)

        let achievements = await achievementResolver(modelContainer)
        let fieldTrips = Self.milestones(from: progress)
        let includesNewToMerian = speciesData.map(Self.isValidNewToMerianMilestone) ?? false

        presenter.enqueueScanMilestoneBatch(
            fieldTrips: fieldTrips,
            achievements: achievements,
            includesNewToMerian: includesNewToMerian
        )
        rememberCompletedScan(scanId)
    }

    /// Re-applies progress after a user changes a saved scan's identification.
    /// These updates are not part of the original scan-completion milestone batch.
    func processIdentificationUpdate(scanId: String) async {
        let progress = await progressResolver(scanId)
        publishProgressEvents(progress)

        for milestone in Self.milestones(from: progress) {
            presenter.enqueueFieldTripProgress(milestone)
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
        inFlightScanIds.removeAll()
        completedScanIds.removeAll()
        completedScanOrder.removeAll()
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

    private func rememberCompletedScan(_ scanId: String) {
        completedScanIds.insert(scanId)
        completedScanOrder.append(scanId)

        if completedScanOrder.count > completedScanLimit {
            let expiredScanId = completedScanOrder.removeFirst()
            completedScanIds.remove(expiredScanId)
        }
    }

    private static func resolveProgress(scanId: String) async -> FieldTripProgressResult? {
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
                if status.jobStatus == .failed { return nil }
            }
            guard isPersisted else {
                MerianLog.general.debug(
                    "Field trip progress deferred because remote scan persistence is not complete."
                )
                return nil
            }

            return try await MerianNetworkClient.shared.applyFieldTripProgress(scanId: scanId)
        } catch {
            MerianLog.general.debug("Field trip progress update failed: \(error, privacy: .private)")
            return nil
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
