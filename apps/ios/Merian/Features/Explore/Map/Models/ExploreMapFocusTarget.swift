import Foundation

struct ExploreMapFocusTarget: Equatable {
    let post: ExploreMapPost

    init(post: ExploreMapPost) {
        self.post = post
    }

    init?(post: ExplorePost, detail: ExplorePostDetail) {
        guard let mapPoint = detail.visibleMapPoint else { return nil }

        self.post = ExploreMapPost(
            postId: post.postId,
            scanId: post.scanId,
            latitude: mapPoint.latitude,
            longitude: mapPoint.longitude,
            coordinateVisibility: mapPoint.coordinateVisibility,
            heroImageUrl: post.heroImageUrl,
            referenceThumbnailUrl: post.referenceThumbnailUrl,
            sharedAt: post.sharedAt,
            authorUserId: post.authorUserId,
            authorName: post.authorName,
            authorUsername: post.authorUsername,
            authorAvatarUrl: post.authorAvatarUrl,
            authorIsPro: post.authorIsPro,
            speciesCommonName: post.speciesCommonName,
            speciesScientificName: post.speciesScientificName,
            petIdentification: post.petIdentification,
            taxonomyKingdom: detail.taxonomyKingdom,
            taxonomyClass: detail.taxonomyClass,
            publicLocationLabel: post.publicLocationLabel,
            locationSharing: .open,
            timeOfDay: post.timeOfDay,
            currentMonth: post.currentMonth,
            weatherCondition: post.weatherCondition,
            weatherTemperatureF: post.weatherTemperatureF,
            likeCount: post.likeCount,
            commentCount: post.commentCount,
            viewerHasLiked: post.viewerHasLiked,
            isOwnedByViewer: post.isOwnedByViewer,
            mediaItems: post.mediaItems
        )
    }
}
