import SwiftData
import SwiftUI

extension InsightSheetViewModel {
    func presentExplore(
        target: InsightExplorePresentationTarget,
        expectedScanId: String,
        expectedGeneration: UInt64
    ) {
        guard isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ) else {
            return
        }
        state.explorePresentationTarget = target
        state.explorePresentationScanId = expectedScanId
        state.explorePresentationGeneration = expectedGeneration
        state.showExploreSheet = true
    }

    func presentExplorePostComposer(
        expectedScanId: String,
        expectedGeneration: UInt64? = nil
    ) {
        guard isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ),
              let postId = state.sharedExplorePostId else {
            return
        }
        state.explorePostComposerPresentationScanId = expectedScanId
        state.explorePostComposerPresentationGeneration = scanBoundActionGeneration
        state.explorePostComposerPresentationPostId = postId
        state.isExplorePostComposerPresented = true
    }

    func presentCommunityIdentificationRequest(
        expectedScanId: String,
        expectedGeneration: UInt64? = nil
    ) {
        guard isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ) else {
            return
        }
        state.communityRequestPresentationScanId = expectedScanId
        state.communityRequestPresentationGeneration = scanBoundActionGeneration
        state.communityRequestPresentationRequestId =
            state.sharedCommunityIdentificationRequestId
        state.isCommunityRequestSheetPresented = true
    }

    func shareToExplore(
        includeFieldNotes: Bool = false,
        fieldNotes: String? = nil,
        hashtags: [String] = [],
        locationSharing: ExplorePostLocationSharing? = nil,
        expectedScanId: String? = nil,
        expectedGeneration: UInt64? = nil,
        modelContext: ModelContext
    ) async {
        guard canShareToExplore,
              expectedGeneration == nil ||
                expectedGeneration == scanBoundActionGeneration,
              let record = fetchActiveLocalRecord(modelContext: modelContext),
              expectedScanId == nil ||
                expectedScanId?.caseInsensitiveCompare(record.id) == .orderedSame,
              !state.isSharingToExplore else { return }

        let scanId = record.id
        let generation = scanBoundActionGeneration
        state.isSharingToExplore = true
        defer {
            if generation == scanBoundActionGeneration {
                state.isSharingToExplore = false
            }
        }

        do {
            let notesForPost = fieldNotes ?? (includeFieldNotes ? shareableFieldNotes : nil)
            let response = try await MerianNetworkClient.shared.shareScanToExplore(
                scan: record,
                fallbackImageData: activeMedia.liveImageData,
                speciesCommonName: resolvedHeaderTitle,
                fieldNotes: notesForPost,
                hashtags: hashtags,
                locationSharing: locationSharing
            )
            cacheSharedExplorePostId(
                response.postId,
                for: scanId,
                generation: generation
            )
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ) else { return }
            state.isExploreFeedVisible = true
            state.sharedExploreHashtags = hashtags
            state.sharedExploreLocationSharing = response.locationSharing ?? locationSharing
            state.exploreFieldNotesArePublic = notesForPost != nil
            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Shared to Explore"
                toastActionTitle = "View"
                toastAction = explorePresentationAction(
                    target: .post,
                    scanId: scanId,
                    generation: generation
                )
            }
        } catch {
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ) else { return }
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = ExploreErrorFormatter.titledMessage("Couldn’t share to Explore", for: error)
            }
        }
    }

    func shareToExplore(
        _ draft: ExplorePostComposerDraft,
        expectedScanId: String,
        expectedGeneration: UInt64,
        modelContext: ModelContext
    ) async -> Bool {
        guard canShareToExplore,
              isPresentingLocalRecord(
                  scanId: expectedScanId,
                  generation: expectedGeneration
              ),
              let record = fetchActiveLocalRecord(modelContext: modelContext),
              record.id.caseInsensitiveCompare(expectedScanId) == .orderedSame,
              !state.isSharingToExplore else { return false }

        let scanId = record.id
        let generation = scanBoundActionGeneration
        state.isSharingToExplore = true
        defer {
            if generation == scanBoundActionGeneration {
                state.isSharingToExplore = false
            }
        }

        do {
            persistComposerPreferredCommonName(draft.selectedCommonName, modelContext: modelContext)
            let response = try await MerianNetworkClient.shared.shareScanToExplore(
                scan: record,
                fallbackImageData: activeMedia.liveImageData,
                speciesCommonName: draft.selectedCommonName,
                fieldNotes: draft.publicFieldNotes,
                hashtags: draft.hashtags,
                locationSharing: draft.locationSharing,
                mediaItems: draft.mediaItems
            )
            cacheSharedExplorePostId(
                response.postId,
                for: scanId,
                generation: generation
            )
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ) else { return true }
            state.isExploreFeedVisible = true
            state.sharedExploreHashtags = draft.hashtags
            state.sharedExploreLocationSharing = response.locationSharing ?? draft.locationSharing
            state.exploreFieldNotesArePublic = draft.publicFieldNotes != nil
            syncComposerFieldNotes(draft.fieldNotes, modelContext: modelContext)
            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Shared to Explore"
                toastActionTitle = "View"
                toastAction = explorePresentationAction(
                    target: .post,
                    scanId: scanId,
                    generation: generation
                )
            }
            return true
        } catch {
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ) else { return false }
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = ExploreErrorFormatter.titledMessage("Couldn’t share to Explore", for: error)
            }
            return false
        }
    }

    func updateExploreFieldNotesVisibility(
        isPublic: Bool,
        expectedScanId: String,
        expectedGeneration: UInt64,
        modelContext: ModelContext
    ) async -> FieldNotesVisibilityUpdateFeedback {
        guard isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ) else {
            return .failure("The presented scan changed before field notes could update")
        }
        return await syncExploreFieldNotesVisibility(
            isPublic: isPublic,
            fieldNotesForPost: shareableFieldNotes,
            expectedScanId: expectedScanId,
            expectedGeneration: expectedGeneration,
            modelContext: modelContext
        )
    }

    func saveFieldNotesAndExploreVisibility(
        _ text: String,
        isPublic: Bool,
        expectedScanId: String,
        expectedGeneration: UInt64,
        modelContext: ModelContext
    ) async -> FieldNotesVisibilityUpdateFeedback {
        guard currentFieldNotesScanId?
            .caseInsensitiveCompare(expectedScanId) == .orderedSame,
              isPresentingLocalRecord(
                  scanId: expectedScanId,
                  generation: expectedGeneration
              ) else {
            return .failure("This observation changed before field notes could save")
        }
        updateFieldNotes(
            text,
            expectedScanId: expectedScanId,
            expectedGeneration: expectedGeneration,
            modelContext: modelContext
        )

        let fieldNotesForPost = FieldNotesRepository.trimmedNonEmptyText(text)
        return await syncExploreFieldNotesVisibility(
            isPublic: isPublic && fieldNotesForPost != nil,
            fieldNotesForPost: fieldNotesForPost,
            expectedScanId: expectedScanId,
            expectedGeneration: expectedGeneration,
            modelContext: modelContext
        )
    }

    private func syncExploreFieldNotesVisibility(
        isPublic: Bool,
        fieldNotesForPost: String?,
        expectedScanId: String,
        expectedGeneration: UInt64,
        modelContext: ModelContext
    ) async -> FieldNotesVisibilityUpdateFeedback {
        guard let scanId = presentedLocalRecordScanId,
              scanId.caseInsensitiveCompare(expectedScanId) == .orderedSame,
              expectedGeneration == scanBoundActionGeneration,
              let postId = state.sharedExplorePostId,
              !state.isUpdatingExploreFieldNotes else {
            return .failure("Field notes visibility is already updating")
        }

        guard !isPublic || fieldNotesForPost != nil else {
            return .failure("Add field notes before publishing them")
        }

        let generation = scanBoundActionGeneration
        state.isUpdatingExploreFieldNotes = true
        defer {
            if generation == scanBoundActionGeneration {
                state.isUpdatingExploreFieldNotes = false
            }
        }

        do {
            if !isPublic, let fieldNotesForPost {
                preserveLocalFieldNotesIfNeeded(fieldNotesForPost, modelContext: modelContext)
            }

            let response = try await MerianNetworkClient.shared.updateExplorePostFieldNotes(
                postId: postId,
                fieldNotes: isPublic ? fieldNotesForPost : nil
            )
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ),
                  state.sharedExplorePostId?
                    .caseInsensitiveCompare(postId) == .orderedSame else {
                return .failure("The presented scan changed while field notes were updating")
            }
            sharedExploreStateRevision &+= 1
            let publicNotes = response.fieldNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            state.exploreFieldNotesArePublic = publicNotes
            HapticManager.shared.triggerSuccessPulse()
            return .success(isPublic: publicNotes)
        } catch {
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ),
                  state.sharedExplorePostId?
                    .caseInsensitiveCompare(postId) == .orderedSame else {
                return .failure("The presented scan changed while field notes were updating")
            }
            HapticManager.shared.triggerErrorThump()
            return .failure(ExploreErrorFormatter.message(for: error))
        }
    }

    func updateExplorePostContent(
        _ draft: ExplorePostComposerDraft,
        expectedScanId: String,
        expectedGeneration: UInt64,
        modelContext: ModelContext
    ) async {
        guard let scanId = presentedLocalRecordScanId,
              scanId.caseInsensitiveCompare(expectedScanId) == .orderedSame,
              expectedGeneration == scanBoundActionGeneration,
              let postId = state.sharedExplorePostId,
              !state.isUpdatingExplorePostContent else { return }

        let generation = scanBoundActionGeneration
        state.isUpdatingExplorePostContent = true
        defer {
            if generation == scanBoundActionGeneration {
                state.isUpdatingExplorePostContent = false
            }
        }

        do {
            persistComposerPreferredCommonName(draft.selectedCommonName, modelContext: modelContext)
            let response = try await MerianNetworkClient.shared.updateExplorePostContent(
                postId: postId,
                speciesCommonName: draft.selectedCommonName,
                fieldNotes: draft.publicFieldNotes,
                hashtags: draft.hashtags,
                locationSharing: draft.locationSharing,
                mediaItems: draft.mediaItems
            )
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ),
                  state.sharedExplorePostId?
                    .caseInsensitiveCompare(postId) == .orderedSame else {
                return
            }
            sharedExploreStateRevision &+= 1
            state.sharedExploreHashtags = response.hashtags ?? draft.hashtags
            state.sharedExploreLocationSharing = response.locationSharing ?? draft.locationSharing
            state.exploreFieldNotesArePublic = response.fieldNotes?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false

            syncComposerFieldNotes(draft.fieldNotes, modelContext: modelContext)

            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Explore post updated"
            }
        } catch {
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ),
                  state.sharedExplorePostId?
                    .caseInsensitiveCompare(postId) == .orderedSame else {
                return
            }
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = ExploreErrorFormatter.titledMessage("Couldn’t update Explore post", for: error)
            }
        }
    }

    func requestCommunityIdentification(
        note: String?,
        locationSharing: ExplorePostLocationSharing,
        expectedScanId: String,
        expectedGeneration: UInt64,
        modelContext: ModelContext
    ) async {
        guard canRequestCommunityIdentification,
              isPresentingLocalRecord(
                  scanId: expectedScanId,
                  generation: expectedGeneration
              ),
              let record = fetchActiveLocalRecord(modelContext: modelContext),
              record.id.caseInsensitiveCompare(expectedScanId) == .orderedSame,
              !state.isRequestingCommunityIdentification else { return }

        let scanId = record.id
        let generation = scanBoundActionGeneration
        state.isRequestingCommunityIdentification = true
        defer {
            if generation == scanBoundActionGeneration {
                state.isRequestingCommunityIdentification = false
            }
        }

        do {
            let request = try await MerianNetworkClient.shared.requestCommunityIdentification(
                scan: record,
                fallbackImageData: activeMedia.liveImageData,
                speciesCommonName: resolvedHeaderTitle,
                note: note,
                locationSharing: locationSharing
            )
            ExploreShareStateStore.setSharedPostId(nil, for: scanId)
            AppEventPublisher.shared.send(.exploreShareStateChanged(scanId: scanId, postId: nil))
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ) else { return }
            sharedExploreStateRevision &+= 1
            state.sharedExplorePostId = nil
            state.isExploreFeedVisible = false
            state.sharedCommunityIdentificationRequestId = request.id
            state.sharedCommunityIdentificationStatus = request.status
            state.sharedExploreLocationSharing = locationSharing
            state.isCommunityRequestSheetPresented = false
            state.communityRequestPresentationScanId = nil
            state.communityRequestPresentationGeneration = nil
            state.communityRequestPresentationRequestId = nil
            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Asked the community"
                toastActionTitle = "View"
                toastAction = explorePresentationAction(
                    target: .communityRequest,
                    scanId: scanId,
                    generation: generation
                )
            }
        } catch {
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ) else { return }
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = ExploreErrorFormatter.titledMessage("Couldn’t ask the community", for: error)
            }
        }
    }

    func updateCommunityIdentificationRequest(
        note: String?,
        locationSharing: ExplorePostLocationSharing,
        expectedScanId: String,
        expectedGeneration: UInt64
    ) async {
        guard let scanId = presentedLocalRecordScanId,
              scanId.caseInsensitiveCompare(expectedScanId) == .orderedSame,
              expectedGeneration == scanBoundActionGeneration,
              let requestId = state.sharedCommunityIdentificationRequestId,
              !state.isRequestingCommunityIdentification else { return }

        let generation = scanBoundActionGeneration
        state.isRequestingCommunityIdentification = true
        defer {
            if generation == scanBoundActionGeneration {
                state.isRequestingCommunityIdentification = false
            }
        }

        do {
            _ = try await MerianNetworkClient.shared.updateCommunityIdentificationRequest(
                requestId: requestId,
                note: note,
                locationSharing: locationSharing
            )
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ),
                  state.sharedCommunityIdentificationRequestId?
                    .caseInsensitiveCompare(requestId) == .orderedSame else {
                return
            }
            sharedExploreStateRevision &+= 1
            state.sharedExploreLocationSharing = locationSharing
            state.isCommunityRequestSheetPresented = false
            state.communityRequestPresentationScanId = nil
            state.communityRequestPresentationGeneration = nil
            state.communityRequestPresentationRequestId = nil
            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Request updated"
                toastActionTitle = "View"
                toastAction = explorePresentationAction(
                    target: .communityRequest,
                    scanId: scanId,
                    generation: generation
                )
            }
        } catch {
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ),
                  state.sharedCommunityIdentificationRequestId?
                    .caseInsensitiveCompare(requestId) == .orderedSame else {
                return
            }
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = ExploreErrorFormatter.titledMessage("Couldn’t update request", for: error)
            }
        }
    }

    private func persistComposerPreferredCommonName(_ name: String, modelContext: ModelContext) {
        guard let scientificName = inferenceEngine?.speciesData?.scientificName else { return }
        let didSave = SpeciesPreferredNameRepository.setPreferredName(
            name,
            for: scientificName,
            modelContext: modelContext
        )
        guard didSave else { return }
        state.preferredCommonName = SpeciesPreferredNameRepository.preferredName(
            for: scientificName,
            modelContext: modelContext
        )
    }

    private func explorePresentationAction(
        target: InsightExplorePresentationTarget,
        scanId: String,
        generation: UInt64
    ) -> () -> Void {
        { [weak self] in
            guard let self,
                  self.isPresentingLocalRecord(
                      scanId: scanId,
                      generation: generation
                  ) else {
                return
            }
            self.presentExplore(
                target: target,
                expectedScanId: scanId,
                expectedGeneration: generation
            )
        }
    }

// Removed presentShareSheet as this logic was extracted into ShareSheetUtility
    func refreshSharedExploreStateFromLocalCache(scanId: String? = nil) {
        guard let resolvedScanId = scanId ?? activeLocalRecordId,
              activeLocalRecord?.id.caseInsensitiveCompare(resolvedScanId) == .orderedSame,
              activeLocalRecordId?.caseInsensitiveCompare(resolvedScanId) == .orderedSame,
              toolbarRecordSnapshot?.scanId.caseInsensitiveCompare(resolvedScanId) == .orderedSame else {
            return
        }
        let cachedPostId = ExploreShareStateStore.sharedPostId(for: resolvedScanId)
        if cachedPostId == nil, state.sharedCommunityIdentificationRequestId != nil {
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
                expectedScanId?.caseInsensitiveCompare(scanId) == .orderedSame,
              expectedGeneration == nil ||
                expectedGeneration == scanBoundActionGeneration else {
            return
        }

        let generation = scanBoundActionGeneration
        sharedExploreStateRequestToken &+= 1
        let requestToken = sharedExploreStateRequestToken
        let requestRevision = sharedExploreStateRevision

        do {
            let shareState = try await MerianNetworkClient.shared.getExploreShareState(scanId: scanId)
            guard !Task.isCancelled else { return }
            guard requestToken == sharedExploreStateRequestToken else { return }
            guard requestRevision == sharedExploreStateRevision else { return }

            ExploreShareStateStore.setSharedPostId(
                shareState.isExploreFeedVisible ? shareState.postId : nil,
                for: scanId
            )
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ) else { return }
            applySharedExploreShareState(shareState, for: scanId, bumpRevision: false)
            state.sharedExploreLocationSharing = shareState.locationSharing
            if shareState.isExploreFeedVisible {
                await refreshExploreFieldNotesVisibility(
                    postId: shareState.postId,
                    scanId: scanId,
                    generation: generation,
                    requestToken: requestToken,
                    requestRevision: requestRevision,
                    modelContext: modelContext
                )
            } else {
                state.exploreFieldNotesArePublic = false
                state.sharedExploreHashtags = []
            }
        } catch {
            guard MerianNetworkClient.shouldAttemptExploreCloudScanRestore(
                after: error
            ),
                  requestToken == sharedExploreStateRequestToken,
                  requestRevision == sharedExploreStateRevision,
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
        requestToken: UInt64,
        requestRevision: UInt64,
        modelContext: ModelContext?
    ) async {
        guard isPresentingLocalRecord(
            scanId: scanId,
            generation: generation
        ),
              requestToken == sharedExploreStateRequestToken,
              requestRevision == sharedExploreStateRevision else { return }

        guard let postId else {
            state.exploreFieldNotesArePublic = false
            state.sharedExploreHashtags = []
            state.sharedExploreLocationSharing = nil
            return
        }

        do {
            let detail = try await MerianNetworkClient.shared.getExplorePostDetail(postId: postId)
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ),
                  requestToken == sharedExploreStateRequestToken,
                  requestRevision == sharedExploreStateRevision,
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

    private func cacheSharedExplorePostId(
        _ postId: String?,
        for scanId: String,
        generation: UInt64
    ) {
        ExploreShareStateStore.setSharedPostId(postId, for: scanId)
        AppEventPublisher.shared.send(.exploreShareStateChanged(scanId: scanId, postId: postId))
        guard isPresentingLocalRecord(
            scanId: scanId,
            generation: generation
        ) else { return }
        applySharedExplorePostId(
            ExploreShareStateStore.sharedPostId(for: scanId),
            for: scanId,
            bumpRevision: true
        )
    }

    private func applySharedExplorePostId(_ postId: String?, for scanId: String?, bumpRevision: Bool) {
        if bumpRevision {
            sharedExploreStateRevision &+= 1
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

        let trimmed = postId?.trimmingCharacters(in: .whitespacesAndNewlines)
        state.sharedExplorePostId = (trimmed?.isEmpty == false) ? trimmed : nil
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
            sharedExploreStateRevision &+= 1
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

        let trimmedPostId = shareState.postId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let feedPostId = shareState.isExploreFeedVisible ? trimmedPostId : nil
        state.sharedExplorePostId = (feedPostId?.isEmpty == false) ? feedPostId : nil
        state.isExploreFeedVisible = state.sharedExplorePostId != nil
        state.sharedCommunityIdentificationRequestId = shareState.communityRequestId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if state.sharedCommunityIdentificationRequestId?.isEmpty == true {
            state.sharedCommunityIdentificationRequestId = nil
        }
        state.sharedCommunityIdentificationStatus = shareState.communityRequestStatus

        if state.sharedExplorePostId == nil {
            state.exploreFieldNotesArePublic = false
        }
    }
}
