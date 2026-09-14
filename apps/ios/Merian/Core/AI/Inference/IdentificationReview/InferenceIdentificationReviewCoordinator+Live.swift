import Foundation

@MainActor
extension InferenceIdentificationReviewCoordinator.Dependencies {
    /// Source-compatible fallback for direct engine construction. App-level
    /// collaborators resolve only when a successful review sync emits effects.
    static var live: Self {
        make(
            sendPostRefresh: { postID in
                AppDIContainer.shared.appEventPublisher.send(
                    .explorePostNeedsRefresh(postId: postID)
                )
            },
            processIdentificationUpdate: { scanID in
                await AppDIContainer.shared.scanMilestoneCoordinator
                    .processIdentificationUpdate(scanId: scanID)
            }
        )
    }

    static func composed(
        eventSender: AppEventPublisher,
        milestoneCoordinator: ScanMilestoneCoordinator
    ) -> Self {
        make(
            sendPostRefresh: { postID in
                eventSender.send(.explorePostNeedsRefresh(postId: postID))
            },
            processIdentificationUpdate: { scanID in
                await milestoneCoordinator.processIdentificationUpdate(
                    scanId: scanID
                )
            }
        )
    }

    private static func make(
        sendPostRefresh: @escaping @MainActor @Sendable (String) -> Void,
        processIdentificationUpdate:
            @escaping @MainActor @Sendable (String) async -> Void
    ) -> Self {
        Self(
            beginOverride: { container, scanID, scientificName in
                let actor = BackgroundDatabaseActor(
                    modelContainer: container
                )
                await actor.beginScanIdentificationOverride(
                    scanId: scanID,
                    scientificName: scientificName
                )
            },
            persistReview: { container, mutation in
                let actor = BackgroundDatabaseActor(
                    modelContainer: container
                )
                await actor.updateScanWithOverride(
                    scanId: mutation.scanID,
                    override: mutation.override,
                    confirmed: mutation.confirmed,
                    newConfirmedSpeciesId: mutation.confirmedSpeciesID,
                    userReviewState: mutation.userReviewState
                )
            },
            clearFlag: { container, scanID in
                let actor = BackgroundDatabaseActor(
                    modelContainer: container
                )
                await actor.updateScanAsUnflagged(scanId: scanID)
            },
            persistSpeciesPatch: { container, scanID, patch in
                let actor = BackgroundDatabaseActor(
                    modelContainer: container
                )
                await actor.updateScanWithOverrideSpeciesData(
                    scanId: scanID,
                    commonName: patch.commonName,
                    hazardType: patch.hazardType,
                    wikipediaOverview: patch.wikipediaOverview,
                    wikipediaUrl: patch.wikipediaURL,
                    referenceImageUrl: patch.referenceImageURL,
                    iucnRedListStatus: patch.iucnRedListStatus,
                    habitatDescription: patch.habitatDescription,
                    gbifTaxonKey: patch.gbifTaxonKey,
                    taxonomy: patch.taxonomy,
                    replacingSpeciesIdentity: patch.replacingSpeciesIdentity
                )
            },
            sharedPostID: { scanID in
                ExploreShareStateStore.sharedPostId(for: scanID)
            },
            sendPostRefresh: sendPostRefresh,
            processIdentificationUpdate: processIdentificationUpdate,
            logSnapshotFailure: { purpose, scanID, error in
                let operation = switch purpose {
                case .confirmation: "confirmAIIdentification"
                case .reset: "resetIdentificationReview"
                }
                MerianLog.data.error(
                    "\(operation, privacy: .public): persistence preflight failed for \(scanID, privacy: .private): \(error, privacy: .private)"
                )
            },
            logSpeciesLookupFailure: { error in
                MerianLog.general.debug(
                    "Identification review species lookup failed: \(error, privacy: .private)"
                )
            },
            logSyncFailure: { error in
                MerianLog.general.debug(
                    "Identification review sync failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
                )
            }
        )
    }
}
