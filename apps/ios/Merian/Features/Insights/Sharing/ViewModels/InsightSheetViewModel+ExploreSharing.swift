import SwiftData
import SwiftUI

extension InsightSheetViewModel {
    func shareToExplore(
        includeFieldNotes: Bool = false,
        fieldNotes: String? = nil,
        hashtags: [String] = [],
        locationSharing: ExplorePostLocationSharing? = nil,
        modelContext: ModelContext
    ) async {
        guard canShareToExplore,
              let record = fetchActiveLocalRecord(modelContext: modelContext),
              !state.isSharingToExplore else { return }

        state.isSharingToExplore = true
        defer { state.isSharingToExplore = false }

        do {
            let scanId = record.id
            let notesForPost = fieldNotes ?? (includeFieldNotes ? shareableFieldNotes : nil)
            let response = try await MerianNetworkClient.shared.shareScanToExplore(
                scan: record,
                fallbackImageData: activeMedia.liveImageData,
                speciesCommonName: resolvedHeaderTitle,
                fieldNotes: notesForPost,
                hashtags: hashtags,
                locationSharing: locationSharing
            )
            cacheSharedExplorePostId(response.postId, for: scanId)
            state.isExploreFeedVisible = true
            state.sharedExploreHashtags = hashtags
            state.sharedExploreLocationSharing = response.locationSharing ?? locationSharing
            state.exploreFieldNotesArePublic = notesForPost != nil
            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Shared to Explore"
                toastActionTitle = "View"
                toastAction = { [weak self] in
                    self?.state.explorePresentationTarget = .post
                    self?.state.showExploreSheet = true
                }
            }
        } catch {
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = ExploreErrorFormatter.titledMessage("Couldn’t share to Explore", for: error)
            }
        }
    }

    func shareToExplore(
        _ draft: ExplorePostComposerDraft,
        modelContext: ModelContext
    ) async -> Bool {
        guard canShareToExplore,
              let record = fetchActiveLocalRecord(modelContext: modelContext),
              !state.isSharingToExplore else { return false }

        state.isSharingToExplore = true
        defer { state.isSharingToExplore = false }

        do {
            let scanId = record.id
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
            cacheSharedExplorePostId(response.postId, for: scanId)
            state.isExploreFeedVisible = true
            state.sharedExploreHashtags = draft.hashtags
            state.sharedExploreLocationSharing = response.locationSharing ?? draft.locationSharing
            state.exploreFieldNotesArePublic = draft.publicFieldNotes != nil
            syncComposerFieldNotes(draft.fieldNotes, modelContext: modelContext)
            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Shared to Explore"
                toastActionTitle = "View"
                toastAction = { [weak self] in
                    self?.state.explorePresentationTarget = .post
                    self?.state.showExploreSheet = true
                }
            }
            return true
        } catch {
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = ExploreErrorFormatter.titledMessage("Couldn’t share to Explore", for: error)
            }
            return false
        }
    }

    func updateExploreFieldNotesVisibility(
        isPublic: Bool,
        modelContext: ModelContext
    ) async -> FieldNotesVisibilityUpdateFeedback {
        await syncExploreFieldNotesVisibility(
            isPublic: isPublic,
            fieldNotesForPost: shareableFieldNotes,
            modelContext: modelContext
        )
    }

    func saveFieldNotesAndExploreVisibility(
        _ text: String,
        isPublic: Bool,
        modelContext: ModelContext
    ) async -> FieldNotesVisibilityUpdateFeedback {
        updateFieldNotes(text, modelContext: modelContext)

        let fieldNotesForPost = FieldNotesRepository.trimmedNonEmptyText(text)
        return await syncExploreFieldNotesVisibility(
            isPublic: isPublic && fieldNotesForPost != nil,
            fieldNotesForPost: fieldNotesForPost,
            modelContext: modelContext
        )
    }

    private func syncExploreFieldNotesVisibility(
        isPublic: Bool,
        fieldNotesForPost: String?,
        modelContext: ModelContext
    ) async -> FieldNotesVisibilityUpdateFeedback {
        guard let postId = state.sharedExplorePostId, !state.isUpdatingExploreFieldNotes else {
            return .failure("Field notes visibility is already updating")
        }

        guard !isPublic || fieldNotesForPost != nil else {
            return .failure("Add field notes before publishing them")
        }

        state.isUpdatingExploreFieldNotes = true
        defer { state.isUpdatingExploreFieldNotes = false }

        do {
            if !isPublic, let fieldNotesForPost {
                preserveLocalFieldNotesIfNeeded(fieldNotesForPost, modelContext: modelContext)
            }

            let response = try await MerianNetworkClient.shared.updateExplorePostFieldNotes(
                postId: postId,
                fieldNotes: isPublic ? fieldNotesForPost : nil
            )
            let publicNotes = response.fieldNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            state.exploreFieldNotesArePublic = publicNotes
            HapticManager.shared.triggerSuccessPulse()
            return .success(isPublic: publicNotes)
        } catch {
            HapticManager.shared.triggerErrorThump()
            return .failure(ExploreErrorFormatter.message(for: error))
        }
    }

    func updateExplorePostContent(
        _ draft: ExplorePostComposerDraft,
        modelContext: ModelContext
    ) async {
        guard let postId = state.sharedExplorePostId, !state.isUpdatingExplorePostContent else { return }

        state.isUpdatingExplorePostContent = true
        defer { state.isUpdatingExplorePostContent = false }

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
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = ExploreErrorFormatter.titledMessage("Couldn’t update Explore post", for: error)
            }
        }
    }

    func requestCommunityIdentification(
        note: String?,
        locationSharing: ExplorePostLocationSharing,
        modelContext: ModelContext
    ) async {
        guard canRequestCommunityIdentification,
              let record = fetchActiveLocalRecord(modelContext: modelContext),
              !state.isRequestingCommunityIdentification else { return }

        state.isRequestingCommunityIdentification = true
        defer { state.isRequestingCommunityIdentification = false }

        do {
            let request = try await MerianNetworkClient.shared.requestCommunityIdentification(
                scan: record,
                fallbackImageData: activeMedia.liveImageData,
                speciesCommonName: resolvedHeaderTitle,
                note: note,
                locationSharing: locationSharing
            )
            ExploreShareStateStore.setSharedPostId(nil, for: record.id)
            AppEventPublisher.shared.send(.exploreShareStateChanged(scanId: record.id, postId: nil))
            state.sharedExplorePostId = nil
            state.isExploreFeedVisible = false
            state.sharedCommunityIdentificationRequestId = request.id
            state.sharedCommunityIdentificationStatus = request.status
            state.sharedExploreLocationSharing = locationSharing
            state.isCommunityRequestSheetPresented = false
            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Asked the community"
                toastActionTitle = "View"
                toastAction = { [weak self] in
                    self?.state.explorePresentationTarget = .communityRequest
                    self?.state.showExploreSheet = true
                }
            }
        } catch {
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = ExploreErrorFormatter.titledMessage("Couldn’t ask the community", for: error)
            }
        }
    }

    func updateCommunityIdentificationRequest(
        note: String?,
        locationSharing: ExplorePostLocationSharing
    ) async {
        guard let requestId = state.sharedCommunityIdentificationRequestId,
              !state.isRequestingCommunityIdentification else { return }

        state.isRequestingCommunityIdentification = true
        defer { state.isRequestingCommunityIdentification = false }

        do {
            _ = try await MerianNetworkClient.shared.updateCommunityIdentificationRequest(
                requestId: requestId,
                note: note,
                locationSharing: locationSharing
            )
            state.sharedExploreLocationSharing = locationSharing
            state.isCommunityRequestSheetPresented = false
            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Request updated"
                toastActionTitle = "View"
                toastAction = { [weak self] in
                    self?.state.explorePresentationTarget = .communityRequest
                    self?.state.showExploreSheet = true
                }
            }
        } catch {
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

// Removed presentShareSheet as this logic was extracted into ShareSheetUtility
    func refreshSharedExploreStateFromLocalCache(scanId: String? = nil) {
        let resolvedScanId = scanId ?? activeLocalRecordId ?? inferenceEngine?.speciesData?.scanId
        let cachedPostId = resolvedScanId.flatMap { ExploreShareStateStore.sharedPostId(for: $0) }
        if cachedPostId == nil, state.sharedCommunityIdentificationRequestId != nil {
            return
        }

        applySharedExplorePostId(
            cachedPostId,
            for: resolvedScanId,
            bumpRevision: true
        )
    }

    func refreshSharedExploreStateFromServer(modelContext: ModelContext? = nil) async {
        let scanId = activeLocalRecordId ?? inferenceEngine?.speciesData?.scanId
        guard let scanId, !scanId.isEmpty else { return }

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
            applySharedExploreShareState(shareState, for: scanId, bumpRevision: false)
            state.sharedExploreLocationSharing = shareState.locationSharing
            if shareState.isExploreFeedVisible {
                await refreshExploreFieldNotesVisibility(
                    postId: shareState.postId,
                    modelContext: modelContext
                )
            } else {
                state.exploreFieldNotesArePublic = false
                state.sharedExploreHashtags = []
            }
        } catch {
            // Keep the optimistic local cache when the authoritative refresh is unavailable.
        }
    }

    private func refreshExploreFieldNotesVisibility(
        postId: String?,
        modelContext: ModelContext?
    ) async {
        guard let postId else {
            state.exploreFieldNotesArePublic = false
            state.sharedExploreHashtags = []
            state.sharedExploreLocationSharing = nil
            return
        }

        do {
            let detail = try await MerianNetworkClient.shared.getExplorePostDetail(postId: postId)
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
            state.exploreFieldNotesArePublic = false
        }
    }
    private func cacheSharedExplorePostId(_ postId: String?, for scanId: String) {
        ExploreShareStateStore.setSharedPostId(postId, for: scanId)
        AppEventPublisher.shared.send(.exploreShareStateChanged(scanId: scanId, postId: postId))
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
