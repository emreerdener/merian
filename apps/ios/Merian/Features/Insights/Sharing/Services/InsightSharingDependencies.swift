import Foundation
import SwiftData

private enum InsightSharingDependencyError: Error {
    case unimplemented
}

@MainActor
struct InsightSharingDependencies {
    let shareScanToExplore: @MainActor (
        _ scan: LocalScanRecord,
        _ fallbackImageData: Data?,
        _ speciesCommonName: String?,
        _ fieldNotes: String?,
        _ hashtags: [String],
        _ locationSharing: ExplorePostLocationSharing?,
        _ mediaItems: [ExplorePostMediaSelection]?
    ) async throws -> ExploreShareResponse
    let updateExplorePostFieldNotes: @MainActor (
        _ postID: String,
        _ fieldNotes: String?
    ) async throws -> ExploreUpdateFieldNotesResponse
    let updateExplorePostContent: @MainActor (
        _ postID: String,
        _ speciesCommonName: String?,
        _ fieldNotes: String?,
        _ hashtags: [String],
        _ locationSharing: ExplorePostLocationSharing,
        _ mediaItems: [ExplorePostMediaSelection]?
    ) async throws -> ExploreUpdateFieldNotesResponse
    let requestCommunityIdentification: @MainActor (
        _ scan: LocalScanRecord,
        _ fallbackImageData: Data?,
        _ speciesCommonName: String?,
        _ note: String?,
        _ locationSharing: ExplorePostLocationSharing?
    ) async throws -> CommunityIdentificationRequest
    let updateCommunityIdentificationRequest: @MainActor (
        _ requestID: String,
        _ note: String?,
        _ locationSharing: ExplorePostLocationSharing
    ) async throws -> CommunityRequestUpdate
    let loadExploreShareState: @MainActor (
        _ scanID: String
    ) async throws -> ExploreScanShareState
    let loadExplorePostDetail: @MainActor (
        _ postID: String
    ) async throws -> ExplorePostDetail
    let shouldAttemptCloudScanRestore: @MainActor (_ error: Error) -> Bool
    let loadCachedPostID: @MainActor (_ scanID: String) -> String?
    let storeCachedPostID: @MainActor (
        _ postID: String?,
        _ scanID: String
    ) -> Void
    let publishShareStateChanged: @MainActor (
        _ scanID: String,
        _ postID: String?
    ) -> Void
    let persistPreferredCommonName: @MainActor (
        _ name: String,
        _ scientificName: String,
        _ modelContext: ModelContext
    ) -> String?
    let successFeedback: @MainActor () -> Void
    let errorFeedback: @MainActor () -> Void

    init(
        shareScanToExplore: @escaping @MainActor (
            _ scan: LocalScanRecord,
            _ fallbackImageData: Data?,
            _ speciesCommonName: String?,
            _ fieldNotes: String?,
            _ hashtags: [String],
            _ locationSharing: ExplorePostLocationSharing?,
            _ mediaItems: [ExplorePostMediaSelection]?
        ) async throws -> ExploreShareResponse = { _, _, _, _, _, _, _ in
            throw InsightSharingDependencyError.unimplemented
        },
        updateExplorePostFieldNotes: @escaping @MainActor (
            _ postID: String,
            _ fieldNotes: String?
        ) async throws -> ExploreUpdateFieldNotesResponse = { _, _ in
            throw InsightSharingDependencyError.unimplemented
        },
        updateExplorePostContent: @escaping @MainActor (
            _ postID: String,
            _ speciesCommonName: String?,
            _ fieldNotes: String?,
            _ hashtags: [String],
            _ locationSharing: ExplorePostLocationSharing,
            _ mediaItems: [ExplorePostMediaSelection]?
        ) async throws -> ExploreUpdateFieldNotesResponse = { _, _, _, _, _, _ in
            throw InsightSharingDependencyError.unimplemented
        },
        requestCommunityIdentification: @escaping @MainActor (
            _ scan: LocalScanRecord,
            _ fallbackImageData: Data?,
            _ speciesCommonName: String?,
            _ note: String?,
            _ locationSharing: ExplorePostLocationSharing?
        ) async throws -> CommunityIdentificationRequest = { _, _, _, _, _ in
            throw InsightSharingDependencyError.unimplemented
        },
        updateCommunityIdentificationRequest: @escaping @MainActor (
            _ requestID: String,
            _ note: String?,
            _ locationSharing: ExplorePostLocationSharing
        ) async throws -> CommunityRequestUpdate = { _, _, _ in
            throw InsightSharingDependencyError.unimplemented
        },
        loadExploreShareState: @escaping @MainActor (
            _ scanID: String
        ) async throws -> ExploreScanShareState = { _ in
            throw InsightSharingDependencyError.unimplemented
        },
        loadExplorePostDetail: @escaping @MainActor (
            _ postID: String
        ) async throws -> ExplorePostDetail = { _ in
            throw InsightSharingDependencyError.unimplemented
        },
        shouldAttemptCloudScanRestore: @escaping @MainActor (
            _ error: Error
        ) -> Bool = { _ in false },
        loadCachedPostID: @escaping @MainActor (
            _ scanID: String
        ) -> String? = { _ in nil },
        storeCachedPostID: @escaping @MainActor (
            _ postID: String?,
            _ scanID: String
        ) -> Void = { _, _ in },
        publishShareStateChanged: @escaping @MainActor (
            _ scanID: String,
            _ postID: String?
        ) -> Void = { _, _ in },
        persistPreferredCommonName: @escaping @MainActor (
            _ name: String,
            _ scientificName: String,
            _ modelContext: ModelContext
        ) -> String? = { _, _, _ in nil },
        successFeedback: @escaping @MainActor () -> Void = {},
        errorFeedback: @escaping @MainActor () -> Void = {}
    ) {
        self.shareScanToExplore = shareScanToExplore
        self.updateExplorePostFieldNotes = updateExplorePostFieldNotes
        self.updateExplorePostContent = updateExplorePostContent
        self.requestCommunityIdentification = requestCommunityIdentification
        self.updateCommunityIdentificationRequest =
            updateCommunityIdentificationRequest
        self.loadExploreShareState = loadExploreShareState
        self.loadExplorePostDetail = loadExplorePostDetail
        self.shouldAttemptCloudScanRestore = shouldAttemptCloudScanRestore
        self.loadCachedPostID = loadCachedPostID
        self.storeCachedPostID = storeCachedPostID
        self.publishShareStateChanged = publishShareStateChanged
        self.persistPreferredCommonName = persistPreferredCommonName
        self.successFeedback = successFeedback
        self.errorFeedback = errorFeedback
    }

    static var live: Self {
        let client = MerianNetworkClient.shared
        let container = AppDIContainer.shared
        let hapticManager = container.hapticManager

        func shareScanToExplore(
            scan: LocalScanRecord,
            fallbackImageData: Data?,
            speciesCommonName: String?,
            fieldNotes: String?,
            hashtags: [String],
            locationSharing: ExplorePostLocationSharing?,
            mediaItems: [ExplorePostMediaSelection]?
        ) async throws -> ExploreShareResponse {
            try await client.shareScanToExplore(
                scan: scan,
                fallbackImageData: fallbackImageData,
                speciesCommonName: speciesCommonName,
                fieldNotes: fieldNotes,
                hashtags: hashtags,
                locationSharing: locationSharing,
                mediaItems: mediaItems
            )
        }

        func updateExplorePostContent(
            postID: String,
            speciesCommonName: String?,
            fieldNotes: String?,
            hashtags: [String],
            locationSharing: ExplorePostLocationSharing,
            mediaItems: [ExplorePostMediaSelection]?
        ) async throws -> ExploreUpdateFieldNotesResponse {
            try await client.updateExplorePostContent(
                postId: postID,
                speciesCommonName: speciesCommonName,
                fieldNotes: fieldNotes,
                hashtags: hashtags,
                locationSharing: locationSharing,
                mediaItems: mediaItems
            )
        }

        func requestCommunityIdentification(
            scan: LocalScanRecord,
            fallbackImageData: Data?,
            speciesCommonName: String?,
            note: String?,
            locationSharing: ExplorePostLocationSharing?
        ) async throws -> CommunityIdentificationRequest {
            try await client.requestCommunityIdentification(
                scan: scan,
                fallbackImageData: fallbackImageData,
                speciesCommonName: speciesCommonName,
                note: note,
                locationSharing: locationSharing
            )
        }

        func updateCommunityIdentificationRequest(
            requestID: String,
            note: String?,
            locationSharing: ExplorePostLocationSharing
        ) async throws -> CommunityRequestUpdate {
            try await client.updateCommunityIdentificationRequest(
                requestId: requestID,
                note: note,
                locationSharing: locationSharing
            )
        }

        return Self(
            shareScanToExplore: shareScanToExplore,
            updateExplorePostFieldNotes: { postID, fieldNotes in
                try await client.updateExplorePostFieldNotes(
                    postId: postID,
                    fieldNotes: fieldNotes
                )
            },
            updateExplorePostContent: updateExplorePostContent,
            requestCommunityIdentification: requestCommunityIdentification,
            updateCommunityIdentificationRequest:
                updateCommunityIdentificationRequest,
            loadExploreShareState: { scanID in
                try await client.getExploreShareState(scanId: scanID)
            },
            loadExplorePostDetail: { postID in
                try await client.getExplorePostDetail(postId: postID)
            },
            shouldAttemptCloudScanRestore: { error in
                MerianNetworkClient.shouldAttemptExploreCloudScanRestore(
                    after: error
                )
            },
            loadCachedPostID: { scanID in
                ExploreShareStateStore.sharedPostId(for: scanID)
            },
            storeCachedPostID: { postID, scanID in
                ExploreShareStateStore.setSharedPostId(postID, for: scanID)
            },
            publishShareStateChanged: { scanID, postID in
                container.appEventPublisher.send(
                    .exploreShareStateChanged(
                        scanId: scanID,
                        postId: postID
                    )
                )
            },
            persistPreferredCommonName: { name, scientificName, modelContext in
                guard SpeciesPreferredNameRepository.setPreferredName(
                    name,
                    for: scientificName,
                    modelContext: modelContext
                ) else {
                    return nil
                }
                return SpeciesPreferredNameRepository.preferredName(
                    for: scientificName,
                    modelContext: modelContext
                )
            },
            successFeedback: {
                hapticManager.triggerSuccessPulse()
            },
            errorFeedback: {
                hapticManager.triggerErrorThump()
            }
        )
    }
}

@MainActor
struct InsightShareButtonDependencies {
    let loadChallengeEventHashtags: @MainActor (
        _ scanID: String
    ) async throws -> [String]
    let loadComposerMedia: @MainActor (
        _ scanID: String
    ) async throws -> [ExplorePostComposerMediaDraft]

    init(
        loadChallengeEventHashtags: @escaping @MainActor (
            _ scanID: String
        ) async throws -> [String] = { _ in
            throw InsightSharingDependencyError.unimplemented
        },
        loadComposerMedia: @escaping @MainActor (
            _ scanID: String
        ) async throws -> [ExplorePostComposerMediaDraft] = { _ in
            throw InsightSharingDependencyError.unimplemented
        }
    ) {
        self.loadChallengeEventHashtags = loadChallengeEventHashtags
        self.loadComposerMedia = loadComposerMedia
    }

    static var live: Self {
        let client = MerianNetworkClient.shared
        return Self(
            loadChallengeEventHashtags: { scanID in
                try await client.getFieldTripChallengeHashtags(scanId: scanID)
            },
            loadComposerMedia: { scanID in
                let payload = try await client.getExploreComposerMedia(
                    scanId: scanID
                )
                return ExplorePostComposerMediaDraft.sourceItems(
                    from: payload.mediaItems
                )
            }
        )
    }
}

@MainActor
struct CommunityRequestDependencies {
    let loadDetail: @MainActor (
        _ requestID: String
    ) async throws -> CommunityIdentificationDetail
    let errorMessage: @MainActor (_ error: Error) -> String

    init(
        loadDetail: @escaping @MainActor (
            _ requestID: String
        ) async throws -> CommunityIdentificationDetail = { _ in
            throw InsightSharingDependencyError.unimplemented
        },
        errorMessage: @escaping @MainActor (
            _ error: Error
        ) -> String = { error in
            ExploreErrorFormatter.message(for: error)
        }
    ) {
        self.loadDetail = loadDetail
        self.errorMessage = errorMessage
    }

    static var live: Self {
        let client = MerianNetworkClient.shared
        return Self(
            loadDetail: { requestID in
                try await client.getCommunityIdentificationDetail(
                    requestId: requestID
                )
            }
        )
    }
}
