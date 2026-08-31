import Foundation
import SwiftData

extension InsightSheetViewModel {
    func refreshSharedExploreStateFromLocalCache(scanId: String? = nil) {
        guard let resolvedScanId = scanId ?? activeLocalRecordId,
              activeLocalRecord?.id.caseInsensitiveCompare(resolvedScanId) ==
                .orderedSame,
              activeLocalRecordId?.caseInsensitiveCompare(resolvedScanId) ==
                .orderedSame,
              toolbarRecordSnapshot?.scanId.caseInsensitiveCompare(
                  resolvedScanId
              ) == .orderedSame else {
            return
        }
        let cachedPostId = sharingDependencies.loadCachedPostID(
            resolvedScanId
        )
        if cachedPostId == nil,
           state.sharedCommunityIdentificationRequestId != nil {
            return
        }

        applySharedExplorePostId(
            cachedPostId,
            for: resolvedScanId,
            bumpRevision: true
        )
    }

    func refreshSharedExploreStateFromServer(
        expectedScanId: String? = nil,
        expectedGeneration: UInt64? = nil,
        modelContext: ModelContext? = nil
    ) async {
        guard let scanId = presentedLocalRecordScanId,
              expectedScanId == nil ||
                expectedScanId?.caseInsensitiveCompare(scanId) ==
                .orderedSame,
              expectedGeneration == nil ||
                expectedGeneration == scanBoundActionGeneration else {
            return
        }

        let generation = scanBoundActionGeneration
        let request = sharingOperations.beginShareStateRequest()

        do {
            let shareState = try await sharingDependencies
                .loadExploreShareState(scanId)
            guard !Task.isCancelled,
                  sharingOperations.isCurrent(request) else { return }

            sharingDependencies.storeCachedPostID(
                shareState.isExploreFeedVisible ? shareState.postId : nil,
                scanId
            )
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ) else { return }
            applySharedExploreShareState(
                shareState,
                for: scanId,
                bumpRevision: false
            )
            state.sharedExploreLocationSharing = shareState.locationSharing
            if shareState.isExploreFeedVisible {
                await refreshExploreFieldNotesVisibility(
                    postId: shareState.postId,
                    scanId: scanId,
                    generation: generation,
                    request: request,
                    modelContext: modelContext
                )
            } else {
                state.exploreFieldNotesArePublic = false
                state.sharedExploreHashtags = []
            }
        } catch {
            guard sharingDependencies.shouldAttemptCloudScanRestore(error),
                  sharingOperations.isCurrent(request),
                  isPresentingLocalRecord(
                      scanId: scanId,
                      generation: generation
                  ) else {
                // Keep the optimistic local cache for unavailable or
                // unconfirmed authoritative reads.
                return
            }

            // A handler-confirmed absent owner row cannot own a valid post or
            // Community request. Clear stale local publication state so the
            // next deliberate action enters guarded owner-row recovery.
            cacheSharedExplorePostId(
                nil,
                for: scanId,
                generation: generation
            )
            state.sharedExploreHashtags = []
        }
    }

    private func refreshExploreFieldNotesVisibility(
        postId: String?,
        scanId: String,
        generation: UInt64,
        request: InsightSharingOperationState.ShareStateRequest,
        modelContext: ModelContext?
    ) async {
        guard isPresentingLocalRecord(
            scanId: scanId,
            generation: generation
        ),
        sharingOperations.isCurrent(request) else { return }

        guard let postId else {
            state.exploreFieldNotesArePublic = false
            state.sharedExploreHashtags = []
            state.sharedExploreLocationSharing = nil
            return
        }

        do {
            let detail = try await sharingDependencies
                .loadExplorePostDetail(postId)
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ),
            sharingOperations.isCurrent(request),
            detail.postId.caseInsensitiveCompare(postId) == .orderedSame,
            state.sharedExplorePostId?
                .caseInsensitiveCompare(postId) == .orderedSame else {
                return
            }
            state.sharedExploreHashtags = detail.hashtags ?? []
            state.sharedExploreLocationSharing = detail.locationSharing
            if let fieldNotes = detail.trimmedFieldNotes {
                state.exploreFieldNotesArePublic = true
                if let modelContext {
                    promotePublishedExploreFieldNotesIfLocalMissing(
                        fieldNotes,
                        modelContext: modelContext
                    )
                }
            } else {
                state.exploreFieldNotesArePublic = false
            }
        } catch {
            // A post-detail read is advisory. Preserve the last confirmed or
            // optimistic visibility on transport failures instead of treating
            // an unavailable read as proof that published notes are private.
        }
    }

    func cacheSharedExplorePostId(
        _ postId: String?,
        for scanId: String,
        generation: UInt64
    ) {
        sharingDependencies.storeCachedPostID(postId, scanId)
        sharingDependencies.publishShareStateChanged(scanId, postId)
        guard isPresentingLocalRecord(
            scanId: scanId,
            generation: generation
        ) else { return }
        applySharedExplorePostId(
            sharingDependencies.loadCachedPostID(scanId),
            for: scanId,
            bumpRevision: true
        )
    }

    private func applySharedExplorePostId(
        _ postId: String?,
        for scanId: String?,
        bumpRevision: Bool
    ) {
        if bumpRevision {
            sharingOperations.recordMutation()
        }

        state.sharedCommunityIdentificationRequestId = nil
        state.sharedCommunityIdentificationStatus = nil
        state.isExploreFeedVisible = false

        guard scanId != nil else {
            state.sharedExplorePostId = nil
            state.exploreFieldNotesArePublic = false
            state.sharedExploreLocationSharing = nil
            return
        }

        let trimmed = postId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        state.sharedExplorePostId = trimmed?.isEmpty == false ? trimmed : nil
        state.isExploreFeedVisible = state.sharedExplorePostId != nil
        if state.sharedExplorePostId == nil {
            state.exploreFieldNotesArePublic = false
            state.sharedExploreLocationSharing = nil
            state.sharedExploreHashtags = []
        }
    }

    private func applySharedExploreShareState(
        _ shareState: ExploreScanShareState,
        for scanId: String?,
        bumpRevision: Bool
    ) {
        if bumpRevision {
            sharingOperations.recordMutation()
        }

        guard scanId != nil else {
            state.sharedExplorePostId = nil
            state.sharedCommunityIdentificationRequestId = nil
            state.sharedCommunityIdentificationStatus = nil
            state.isExploreFeedVisible = false
            state.exploreFieldNotesArePublic = false
            state.sharedExploreLocationSharing = nil
            return
        }

        let trimmedPostId = shareState.postId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let feedPostId = shareState.isExploreFeedVisible
            ? trimmedPostId
            : nil
        state.sharedExplorePostId = feedPostId?.isEmpty == false
            ? feedPostId
            : nil
        state.isExploreFeedVisible = state.sharedExplorePostId != nil
        state.sharedCommunityIdentificationRequestId =
            shareState.communityRequestId?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        if state.sharedCommunityIdentificationRequestId?.isEmpty == true {
            state.sharedCommunityIdentificationRequestId = nil
        }
        state.sharedCommunityIdentificationStatus =
            shareState.communityRequestStatus

        if state.sharedExplorePostId == nil {
            state.exploreFieldNotesArePublic = false
        }
    }
}
