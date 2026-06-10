import SwiftData
import SwiftUI

extension InsightSheetViewModel {
    func shareToExplore(
        includeFieldNotes: Bool = false,
        fieldNotes: String? = nil,
        hashtags: [String] = [],
        locationSharing: ExplorePostLocationSharing = .obscured,
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
                fieldNotes: notesForPost,
                hashtags: hashtags,
                locationSharing: locationSharing
            )
            appSettings.hasUnseenExplorePost = true
            cacheSharedExplorePostId(response.postId, for: scanId)
            state.sharedExploreHashtags = hashtags
            state.exploreFieldNotesArePublic = notesForPost != nil
            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Shared to Explore"
                toastActionTitle = "View"
                toastAction = { [weak self] in
                    self?.state.showExploreSheet = true
                }
            }
        } catch {
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = ExploreErrorFormatter.message(for: error)
            }
        }
    }

    func shareToExplore(
        _ draft: ExplorePostComposerDraft,
        modelContext: ModelContext
    ) async {
        guard canShareToExplore,
              let record = fetchActiveLocalRecord(modelContext: modelContext),
              !state.isSharingToExplore else { return }

        state.isSharingToExplore = true
        defer { state.isSharingToExplore = false }

        do {
            let scanId = record.id
            let response = try await MerianNetworkClient.shared.shareScanToExplore(
                scan: record,
                fieldNotes: draft.publicFieldNotes,
                hashtags: draft.hashtags,
                locationSharing: draft.locationSharing
            )
            appSettings.hasUnseenExplorePost = true
            cacheSharedExplorePostId(response.postId, for: scanId)
            state.sharedExploreHashtags = draft.hashtags
            state.exploreFieldNotesArePublic = draft.publicFieldNotes != nil
            syncComposerFieldNotes(draft.fieldNotes, modelContext: modelContext)
            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Shared to Explore"
                toastActionTitle = "View"
                toastAction = { [weak self] in
                    self?.state.showExploreSheet = true
                }
            }
        } catch {
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = ExploreErrorFormatter.message(for: error)
            }
        }
    }

    func updateExploreFieldNotesVisibility(
        isPublic: Bool,
        modelContext: ModelContext
    ) async -> FieldNotesVisibilityUpdateFeedback {
        guard let postId = state.sharedExplorePostId, !state.isUpdatingExploreFieldNotes else {
            return .failure("Field notes visibility is already updating")
        }

        guard !isPublic || shareableFieldNotes != nil else {
            return .failure("Add field notes before publishing them")
        }

        state.isUpdatingExploreFieldNotes = true
        defer { state.isUpdatingExploreFieldNotes = false }

        do {
            if !isPublic, let shareableFieldNotes {
                preserveLocalFieldNotesIfNeeded(shareableFieldNotes, modelContext: modelContext)
            }

            let response = try await MerianNetworkClient.shared.updateExplorePostFieldNotes(
                postId: postId,
                fieldNotes: isPublic ? shareableFieldNotes : nil
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
            let response = try await MerianNetworkClient.shared.updateExplorePostContent(
                postId: postId,
                fieldNotes: draft.publicFieldNotes,
                hashtags: draft.hashtags,
                locationSharing: draft.locationSharing
            )
            state.sharedExploreHashtags = response.hashtags ?? draft.hashtags
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
                state.toastMessage = ExploreErrorFormatter.message(for: error)
            }
        }
    }

// Removed presentShareSheet as this logic was extracted into ShareSheetUtility
    func refreshSharedExploreStateFromLocalCache(scanId: String? = nil) {
        let resolvedScanId = scanId ?? activeLocalRecordId ?? inferenceEngine?.speciesData?.scanId
        applySharedExplorePostId(
            resolvedScanId.flatMap { ExploreShareStateStore.sharedPostId(for: $0) },
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

            ExploreShareStateStore.setSharedPostId(shareState.postId, for: scanId)
            applySharedExplorePostId(shareState.postId, for: scanId, bumpRevision: false)
            await refreshExploreFieldNotesVisibility(
                postId: shareState.postId,
                modelContext: modelContext
            )
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
            return
        }

        do {
            let detail = try await MerianNetworkClient.shared.getExplorePostDetail(postId: postId)
            state.sharedExploreHashtags = detail.hashtags ?? []
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

        guard scanId != nil else {
            state.sharedExplorePostId = nil
            state.exploreFieldNotesArePublic = false
            return
        }

        let trimmed = postId?.trimmingCharacters(in: .whitespacesAndNewlines)
        state.sharedExplorePostId = (trimmed?.isEmpty == false) ? trimmed : nil
        if state.sharedExplorePostId == nil {
            state.exploreFieldNotesArePublic = false
        }
    }
}
