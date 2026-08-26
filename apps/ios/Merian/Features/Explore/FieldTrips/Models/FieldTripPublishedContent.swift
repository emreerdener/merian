import Foundation

struct FieldTripPublishedContent: Identifiable, Equatable {
    enum Kind: Equatable {
        case outingPublication
        case eventEntry
    }

    let id: String
    let kind: Kind
    let title: String
    let publicAuthorDisplayName: String
    let contextTitle: String?
    let body: String?
    var likeCount: Int
    var commentCount: Int
    var viewerHasLiked: Bool
    let items: [FieldTripPublishedContentItem]

    init(publication: FieldTripPublicationDetail) {
        id = publication.publicationId
        kind = .outingPublication
        title = publication.title
        publicAuthorDisplayName = publication.publicAuthorDisplayName
        contextTitle = nil
        body = Self.preferredBody(
            publication.description,
            fallback: publication.aiSummary
        )
        likeCount = publication.likeCount
        commentCount = publication.commentCount
        viewerHasLiked = publication.viewerHasLiked
        items = publication.items.map(FieldTripPublishedContentItem.init)
    }

    init(eventEntry: FieldTripChallengeEntryDetail) {
        id = eventEntry.entryId
        kind = .eventEntry
        title = eventEntry.title
        publicAuthorDisplayName = eventEntry.publicAuthorDisplayName
        contextTitle = eventEntry.challengeTitle
        body = Self.preferredBody(eventEntry.description, fallback: nil)
        likeCount = eventEntry.likeCount
        commentCount = eventEntry.commentCount
        viewerHasLiked = eventEntry.viewerHasLiked
        items = eventEntry.items.map(FieldTripPublishedContentItem.init)
    }

    private static func preferredBody(_ body: String?, fallback: String?) -> String? {
        let trimmedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedBody, !trimmedBody.isEmpty {
            return trimmedBody
        }

        let trimmedFallback = fallback?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedFallback, !trimmedFallback.isEmpty {
            return trimmedFallback
        }

        return nil
    }
}

struct FieldTripPublishedContentItem: Identifiable, Equatable {
    let id: String
    let prompt: String
    let displayName: String
    let imageURLString: String?

    init(publicationItem: FieldTripPublicationItem) {
        id = publicationItem.publicationItemId
        prompt = publicationItem.prompt
        displayName = Self.displayName(
            commonName: publicationItem.commonName,
            scientificName: publicationItem.scientificName,
            prompt: publicationItem.prompt
        )
        imageURLString = publicationItem.heroImageUrl ?? publicationItem.referenceImageUrl
    }

    init(eventEntryItem: FieldTripChallengeEntryItem) {
        id = eventEntryItem.entryItemId
        prompt = eventEntryItem.prompt
        displayName = Self.displayName(
            commonName: eventEntryItem.commonName,
            scientificName: eventEntryItem.scientificName,
            prompt: eventEntryItem.prompt
        )
        imageURLString = eventEntryItem.heroImageUrl ?? eventEntryItem.referenceImageUrl
    }

    private static func displayName(
        commonName: String?,
        scientificName: String?,
        prompt: String
    ) -> String {
        for candidate in [commonName, scientificName] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                return trimmed
            }
        }
        return prompt
    }
}

struct FieldTripPublishedContentLikeResult: Equatable {
    let viewerHasLiked: Bool
    let likeCount: Int
    let commentCount: Int?
}

struct FieldTripPublishedContentCommentResult {
    let comment: ExploreComment
    let commentCount: Int
}
