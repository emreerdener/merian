import Foundation

struct FieldTripPublishedContentEndpoint {
    let loadContent: @MainActor () async throws -> FieldTripPublishedContent
    let loadComments: @MainActor () async throws -> [ExploreComment]
    let setLike: @MainActor (Bool) async throws -> FieldTripPublishedContentLikeResult
    let createComment: @MainActor (String) async throws -> FieldTripPublishedContentCommentResult

    static func outingPublication(
        publicationId: String,
        loadDetail: @escaping @MainActor (String) async throws -> FieldTripPublicationDetail = {
            try await MerianNetworkClient.shared.getFieldTripPublication(publicationId: $0)
        },
        comments: @escaping @MainActor (String) async throws -> [ExploreComment] = {
            try await MerianNetworkClient.shared.getFieldTripComments(publicationId: $0)
        },
        like: @escaping @MainActor (String, Bool) async throws -> FieldTripLikeResponse = {
            try await MerianNetworkClient.shared.setFieldTripLike(publicationId: $0, liked: $1)
        },
        comment: @escaping @MainActor (String, String) async throws -> FieldTripCreateCommentResponse = {
            try await MerianNetworkClient.shared.createFieldTripComment(publicationId: $0, body: $1)
        }
    ) -> Self {
        Self(
            loadContent: {
                FieldTripPublishedContent(publication: try await loadDetail(publicationId))
            },
            loadComments: {
                try await comments(publicationId)
            },
            setLike: { isLiked in
                let response = try await like(publicationId, isLiked)
                return FieldTripPublishedContentLikeResult(
                    viewerHasLiked: response.viewerHasLiked,
                    likeCount: response.likeCount,
                    commentCount: response.commentCount
                )
            },
            createComment: { body in
                let response = try await comment(publicationId, body)
                return FieldTripPublishedContentCommentResult(
                    comment: response.comment,
                    commentCount: response.commentCount
                )
            }
        )
    }

    static func eventEntry(
        entryId: String,
        loadDetail: @escaping @MainActor (String) async throws -> FieldTripChallengeEntryDetail = {
            try await MerianNetworkClient.shared.getFieldTripChallengeEntry(entryId: $0)
        },
        comments: @escaping @MainActor (String) async throws -> [ExploreComment] = {
            try await MerianNetworkClient.shared.getFieldTripChallengeEntryComments(entryId: $0)
        },
        like: @escaping @MainActor (String, Bool) async throws -> FieldTripChallengeEntryLikeResponse = {
            try await MerianNetworkClient.shared.setFieldTripChallengeEntryLike(entryId: $0, liked: $1)
        },
        comment: @escaping @MainActor (String, String) async throws -> FieldTripCreateCommentResponse = {
            try await MerianNetworkClient.shared.createFieldTripChallengeEntryComment(entryId: $0, body: $1)
        }
    ) -> Self {
        Self(
            loadContent: {
                FieldTripPublishedContent(eventEntry: try await loadDetail(entryId))
            },
            loadComments: {
                try await comments(entryId)
            },
            setLike: { isLiked in
                let response = try await like(entryId, isLiked)
                return FieldTripPublishedContentLikeResult(
                    viewerHasLiked: response.viewerHasLiked,
                    likeCount: response.likeCount,
                    commentCount: response.commentCount
                )
            },
            createComment: { body in
                let response = try await comment(entryId, body)
                return FieldTripPublishedContentCommentResult(
                    comment: response.comment,
                    commentCount: response.commentCount
                )
            }
        )
    }
}
