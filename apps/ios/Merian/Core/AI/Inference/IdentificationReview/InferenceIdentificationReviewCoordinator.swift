import Foundation
import SwiftData

struct IdentificationReviewSpeciesPatch: Sendable {
    let commonName: String
    let hazardType: String
    let wikipediaOverview: String?
    let wikipediaURL: String?
    let referenceImageURL: String?
    let iucnRedListStatus: String?
    let habitatDescription: String?
    let gbifTaxonKey: Int?
    let taxonomy: TaxonomyData?
    let replacingSpeciesIdentity: Bool
}

/// Owns identification-review action generations, serialized persistence, and
/// post-cloud effects. Workflow sequencing belongs to
/// `InferenceReviewWorkflowCoordinator`; observable species and media commits
/// route through `InferenceSpeciesPresentationCoordinator` behind the engine
/// facade.
@MainActor
final class InferenceIdentificationReviewCoordinator {
    struct Dependencies {
        let beginOverride:
            @MainActor @Sendable (ModelContainer, String, String) async -> Void
        let persistReview:
            @MainActor @Sendable (
                ModelContainer,
                InferenceIdentificationReviewMutation
            ) async -> Void
        let clearFlag:
            @MainActor @Sendable (ModelContainer, String) async -> Void
        let persistSpeciesPatch:
            @MainActor @Sendable (
                ModelContainer,
                String,
                IdentificationReviewSpeciesPatch
            ) async -> Void
        let sharedPostID: @MainActor @Sendable (String) -> String?
        let sendPostRefresh: @MainActor @Sendable (String) -> Void
        let processIdentificationUpdate:
            @MainActor @Sendable (String) async -> Void
        let logSnapshotFailure:
            @MainActor @Sendable (SnapshotPurpose, String, Error) -> Void
        let logSpeciesLookupFailure:
            @MainActor @Sendable (Error) -> Void
        let logSyncFailure: @MainActor @Sendable (Error) -> Void
    }

    enum SnapshotPurpose: Sendable, Equatable {
        case confirmation
        case reset
    }

    enum SnapshotResult {
        case success(InferenceReviewSnapshot?)
        case failure
    }

    enum SpeciesLookupResult {
        case record(InferenceSpeciesDictionaryRecord)
        case missing
        case failure
    }

    private let writeCoordinator: InferenceWriteCoordinator
    private let reviewService: InferenceIdentificationReviewService
    private let snapshotService: InferenceReviewSnapshotService
    private let dependencies: Dependencies

    init(
        writeCoordinator: InferenceWriteCoordinator,
        reviewService: InferenceIdentificationReviewService,
        snapshotService: InferenceReviewSnapshotService,
        dependencies: Dependencies
    ) {
        self.writeCoordinator = writeCoordinator
        self.reviewService = reviewService
        self.snapshotService = snapshotService
        self.dependencies = dependencies
    }

    var isAuthTransitionFenceActive: Bool {
        writeCoordinator.isAuthTransitionFenceActive
    }

    func beginReviewAction(scanId: String) -> UInt64 {
        writeCoordinator.beginIdentificationAction(
            scanId: scanId,
            channel: .review
        )
    }

    func beginConfirmationAction(scanId: String) -> UInt64 {
        writeCoordinator.beginIdentificationAction(
            scanId: scanId,
            channel: .confirmation
        )
    }

    func beginFlagAction(scanId: String) -> UInt64 {
        writeCoordinator.beginIdentificationAction(
            scanId: scanId,
            channel: .legacyFlag
        )
    }

    func isReviewActionCurrent(
        scanId: String,
        generation: UInt64
    ) -> Bool {
        writeCoordinator.isIdentificationActionCurrent(
            scanId: scanId,
            generation: generation,
            channel: .review
        )
    }

    func isFlagActionCurrent(
        scanId: String,
        generation: UInt64
    ) -> Bool {
        writeCoordinator.isIdentificationActionCurrent(
            scanId: scanId,
            generation: generation,
            channel: .legacyFlag
        )
    }

    @discardableResult
    func enqueueWrite(
        scanId: String,
        actionGeneration: UInt64,
        channel: InferenceWriteCoordinator.IdentificationChannel = .review,
        operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never>? {
        writeCoordinator.enqueueIdentificationWrite(
            scanId: scanId,
            actionGeneration: actionGeneration,
            channel: channel,
            operation: operation
        )
    }

    func loadSnapshot(
        scanId: String,
        modelContext: ModelContext,
        purpose: SnapshotPurpose
    ) -> SnapshotResult {
        do {
            return .success(try snapshotService.load(scanId, modelContext))
        } catch {
            dependencies.logSnapshotFailure(purpose, scanId, error)
            return .failure
        }
    }

    func loadSpecies(scientificName: String) async -> SpeciesLookupResult {
        do {
            if let record = try await reviewService.loadSpecies(
                scientificName: scientificName
            ) {
                return .record(record)
            }
            return .missing
        } catch {
            dependencies.logSpeciesLookupFailure(error)
            return .failure
        }
    }

    func loadSpeciesIDIfAvailable(scientificName: String) async -> String? {
        try? await reviewService.loadSpeciesID(scientificName: scientificName)
    }

    @discardableResult
    func enqueueOverrideAdmission(
        scanId: String,
        scientificName: String,
        actionGeneration: UInt64,
        modelContainer: ModelContainer
    ) -> Task<Void, Never>? {
        let beginOverride = dependencies.beginOverride
        return enqueueWrite(
            scanId: scanId,
            actionGeneration: actionGeneration
        ) {
            await beginOverride(modelContainer, scanId, scientificName)
        }
    }

    @discardableResult
    func enqueueReviewMutation(
        _ mutation: InferenceIdentificationReviewMutation,
        actionGeneration: UInt64,
        channel: InferenceWriteCoordinator.IdentificationChannel = .review,
        modelContainer: ModelContainer?
    ) -> Task<Void, Never>? {
        let persistReview = dependencies.persistReview
        return enqueueWrite(
            scanId: mutation.scanID,
            actionGeneration: actionGeneration,
            channel: channel
        ) { [weak self] in
            if let modelContainer {
                await persistReview(modelContainer, mutation)
            }
            await self?.syncReview(mutation)
        }
    }

    func enqueueFlagReset(
        scanId: String,
        actionGeneration: UInt64,
        modelContainer: ModelContainer
    ) {
        let clearFlag = dependencies.clearFlag
        enqueueWrite(
            scanId: scanId,
            actionGeneration: actionGeneration,
            channel: .legacyFlag
        ) {
            await clearFlag(modelContainer, scanId)
        }
    }

    func enqueueSpeciesPatch(
        _ patch: IdentificationReviewSpeciesPatch,
        scanId: String,
        actionGeneration: UInt64,
        modelContainer: ModelContainer
    ) {
        let persistSpeciesPatch = dependencies.persistSpeciesPatch
        enqueueWrite(
            scanId: scanId,
            actionGeneration: actionGeneration
        ) {
            await persistSpeciesPatch(modelContainer, scanId, patch)
        }
    }

    private func syncReview(
        _ mutation: InferenceIdentificationReviewMutation
    ) async {
        do {
            try await reviewService.syncReview(mutation)
            if let postID = dependencies.sharedPostID(mutation.scanID) {
                dependencies.sendPostRefresh(postID)
            }
            await dependencies.processIdentificationUpdate(mutation.scanID)
        } catch {
            dependencies.logSyncFailure(error)
        }
    }
}
