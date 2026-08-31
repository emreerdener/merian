import Foundation
import SwiftData

extension InsightSheetViewModel {
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
              let record = fetchActiveLocalRecord(
                  modelContext: modelContext
              ),
              expectedScanId == nil ||
                expectedScanId?.caseInsensitiveCompare(record.id) ==
                .orderedSame,
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
            let notesForPost = fieldNotes ??
                (includeFieldNotes ? shareableFieldNotes : nil)
            let response = try await sharingDependencies.shareScanToExplore(
                record,
                activeMedia.liveImageData,
                resolvedHeaderTitle,
                notesForPost,
                hashtags,
                locationSharing,
                nil
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
            state.sharedExploreLocationSharing =
                response.locationSharing ?? locationSharing
            state.exploreFieldNotesArePublic = notesForPost != nil
            sharingDependencies.successFeedback()
            state.toastMessage = .success(
                "Shared to Explore",
                action: .viewExplorePost
            )
            toastAction = explorePresentationAction(
                target: .post,
                scanId: scanId,
                generation: generation
            )
        } catch {
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ) else { return }
            sharingDependencies.errorFeedback()
            state.toastMessage = .error(
                ExploreErrorFormatter.titledMessage(
                    "Couldn’t share to Explore",
                    for: error
                )
            )
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
              let record = fetchActiveLocalRecord(
                  modelContext: modelContext
              ),
              record.id.caseInsensitiveCompare(expectedScanId) ==
                .orderedSame,
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
            persistComposerPreferredCommonName(
                draft.selectedCommonName,
                modelContext: modelContext
            )
            let response = try await sharingDependencies.shareScanToExplore(
                record,
                activeMedia.liveImageData,
                draft.selectedCommonName,
                draft.publicFieldNotes,
                draft.hashtags,
                draft.locationSharing,
                draft.mediaItems
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
            state.sharedExploreLocationSharing =
                response.locationSharing ?? draft.locationSharing
            state.exploreFieldNotesArePublic =
                draft.publicFieldNotes != nil
            syncComposerFieldNotes(
                draft.fieldNotes,
                modelContext: modelContext
            )
            sharingDependencies.successFeedback()
            state.toastMessage = .success(
                "Shared to Explore",
                action: .viewExplorePost
            )
            toastAction = explorePresentationAction(
                target: .post,
                scanId: scanId,
                generation: generation
            )
            return true
        } catch {
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ) else { return false }
            sharingDependencies.errorFeedback()
            state.toastMessage = .error(
                ExploreErrorFormatter.titledMessage(
                    "Couldn’t share to Explore",
                    for: error
                )
            )
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
            return .failure(
                "The presented scan changed before field notes could update"
            )
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
            return .failure(
                "This observation changed before field notes could save"
            )
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
                preserveLocalFieldNotesIfNeeded(
                    fieldNotesForPost,
                    modelContext: modelContext
                )
            }

            let response = try await sharingDependencies
                .updateExplorePostFieldNotes(
                    postId,
                    isPublic ? fieldNotesForPost : nil
                )
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ),
            state.sharedExplorePostId?
                .caseInsensitiveCompare(postId) == .orderedSame else {
                return .failure(
                    "The presented scan changed while field notes were updating"
                )
            }
            sharingOperations.recordMutation()
            let publicNotes = response.fieldNotes?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false
            state.exploreFieldNotesArePublic = publicNotes
            sharingDependencies.successFeedback()
            return .success(isPublic: publicNotes)
        } catch {
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ),
            state.sharedExplorePostId?
                .caseInsensitiveCompare(postId) == .orderedSame else {
                return .failure(
                    "The presented scan changed while field notes were updating"
                )
            }
            sharingDependencies.errorFeedback()
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
            persistComposerPreferredCommonName(
                draft.selectedCommonName,
                modelContext: modelContext
            )
            let response = try await sharingDependencies
                .updateExplorePostContent(
                    postId,
                    draft.selectedCommonName,
                    draft.publicFieldNotes,
                    draft.hashtags,
                    draft.locationSharing,
                    draft.mediaItems
                )
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ),
            state.sharedExplorePostId?
                .caseInsensitiveCompare(postId) == .orderedSame else {
                return
            }
            sharingOperations.recordMutation()
            state.sharedExploreHashtags = response.hashtags ?? draft.hashtags
            state.sharedExploreLocationSharing =
                response.locationSharing ?? draft.locationSharing
            state.exploreFieldNotesArePublic = response.fieldNotes?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false

            syncComposerFieldNotes(
                draft.fieldNotes,
                modelContext: modelContext
            )

            sharingDependencies.successFeedback()
            state.toastMessage = .success("Explore post updated")
        } catch {
            guard isPresentingLocalRecord(
                scanId: scanId,
                generation: generation
            ),
            state.sharedExplorePostId?
                .caseInsensitiveCompare(postId) == .orderedSame else {
                return
            }
            sharingDependencies.errorFeedback()
            state.toastMessage = .error(
                ExploreErrorFormatter.titledMessage(
                    "Couldn’t update Explore post",
                    for: error
                )
            )
        }
    }

    private func persistComposerPreferredCommonName(
        _ name: String,
        modelContext: ModelContext
    ) {
        guard let scientificName = inferenceEngine?.speciesData?
            .scientificName else { return }
        guard let preferredName = sharingDependencies
            .persistPreferredCommonName(
                name,
                scientificName,
                modelContext
            ) else {
            return
        }
        state.preferredCommonName = preferredName
    }
}
