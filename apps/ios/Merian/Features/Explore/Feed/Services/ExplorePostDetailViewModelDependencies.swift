extension ExplorePostDetailViewModel.Dependencies {
    static let live = Self(
        loadDetail: { postId in
            try await MerianNetworkClient.shared.getExplorePostDetail(postId: postId)
        },
        loadComposerMedia: { postId in
            try await MerianNetworkClient.shared.getExploreComposerMedia(postId: postId)
        },
        updateFieldNotes: { postId, fieldNotes in
            try await MerianNetworkClient.shared.updateExplorePostFieldNotes(
                postId: postId,
                fieldNotes: fieldNotes
            )
        },
        updateContent: { postId, commonName, fieldNotes, hashtags, locationSharing, mediaItems in
            try await MerianNetworkClient.shared.updateExplorePostContent(
                postId: postId,
                speciesCommonName: commonName,
                fieldNotes: fieldNotes,
                hashtags: hashtags,
                locationSharing: locationSharing,
                mediaItems: mediaItems
            )
        },
        errorMessage: { ExploreErrorFormatter.message(for: $0) }
    )
}
