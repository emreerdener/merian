@testable import Merian
import Testing

@MainActor
struct FieldTripPublishedContentViewModelTests {
    @Test func normalizedContentMapsOutingAndEventDetails() {
        let outing = FieldTripPublishedContent(
            publication: FieldTripTestFixtures.publicationDetail(
                description: "   ",
                aiSummary: "  A generated summary.  "
            )
        )
        let event = FieldTripPublishedContent(
            eventEntry: FieldTripTestFixtures.eventEntryDetail()
        )

        #expect(outing.id == "publication-1")
        #expect(outing.kind == .outingPublication)
        #expect(outing.contextTitle == nil)
        #expect(outing.body == "A generated summary.")
        #expect(outing.items.first?.displayName == "Northern Cardinal")
        #expect(
            outing.items.first?.imageURLString ==
                "https://media.merian.app/cardinal.webp"
        )

        #expect(event.id == "entry-1")
        #expect(event.kind == .eventEntry)
        #expect(event.contextTitle == "Summer Event")
        #expect(event.items.first?.displayName == "Bombus impatiens")
        #expect(
            event.items.first?.imageURLString ==
                "https://media.merian.app/bee.webp"
        )
    }

    @Test func outingEndpointAdaptsIdentifiersAndResponses() async throws {
        var calls: [String] = []
        let endpoint = FieldTripPublishedContentEndpoint.outingPublication(
            publicationId: "publication-1",
            loadDetail: { publicationId in
                calls.append("load:\(publicationId)")
                return FieldTripTestFixtures.publicationDetail()
            },
            comments: { publicationId in
                calls.append("comments:\(publicationId)")
                return [FieldTripTestFixtures.comment()]
            },
            like: { publicationId, isLiked in
                calls.append("like:\(publicationId):\(isLiked)")
                return FieldTripLikeResponse(
                    publicationId: publicationId,
                    viewerHasLiked: isLiked,
                    likeCount: 8,
                    commentCount: 4
                )
            },
            comment: { publicationId, body in
                calls.append("comment:\(publicationId):\(body)")
                return FieldTripCreateCommentResponse(
                    comment: FieldTripTestFixtures.comment(body: body),
                    commentCount: 5
                )
            }
        )

        let content = try await endpoint.loadContent()
        let comments = try await endpoint.loadComments()
        let like = try await endpoint.setLike(true)
        let comment = try await endpoint.createComment("Great outing")

        #expect(content.kind == .outingPublication)
        #expect(comments.count == 1)
        #expect(like == FieldTripPublishedContentLikeResult(
            viewerHasLiked: true,
            likeCount: 8,
            commentCount: 4
        ))
        #expect(comment.comment.body == "Great outing")
        #expect(comment.commentCount == 5)
        #expect(calls == [
            "load:publication-1",
            "comments:publication-1",
            "like:publication-1:true",
            "comment:publication-1:Great outing"
        ])
    }

    @Test func eventEndpointAdaptsIdentifiersAndResponses() async throws {
        var calls: [String] = []
        let endpoint = FieldTripPublishedContentEndpoint.eventEntry(
            entryId: "entry-1",
            loadDetail: { entryId in
                calls.append("load:\(entryId)")
                return FieldTripTestFixtures.eventEntryDetail()
            },
            comments: { entryId in
                calls.append("comments:\(entryId)")
                return []
            },
            like: { entryId, isLiked in
                calls.append("like:\(entryId):\(isLiked)")
                return FieldTripChallengeEntryLikeResponse(
                    entryId: entryId,
                    viewerHasLiked: isLiked,
                    likeCount: 6,
                    commentCount: nil
                )
            },
            comment: { entryId, body in
                calls.append("comment:\(entryId):\(body)")
                return FieldTripCreateCommentResponse(
                    comment: FieldTripTestFixtures.comment(body: body),
                    commentCount: 3
                )
            }
        )

        let content = try await endpoint.loadContent()
        _ = try await endpoint.loadComments()
        let like = try await endpoint.setLike(false)
        _ = try await endpoint.createComment("Seasonal find")

        #expect(content.kind == .eventEntry)
        #expect(!like.viewerHasLiked)
        #expect(like.likeCount == 6)
        #expect(calls == [
            "load:entry-1",
            "comments:entry-1",
            "like:entry-1:false",
            "comment:entry-1:Seasonal find"
        ])
    }

    @Test func optimisticLikeRollsBackExactlyWhenTheEndpointFails() async {
        let original = FieldTripPublishedContent(
            publication: FieldTripTestFixtures.publicationDetail()
        )
        var errorFeedbackCount = 0
        let viewModel = FieldTripPublishedContentViewModel(
            dependencies: FieldTripPublishedContentViewModel.Dependencies(
                endpoint: FieldTripPublishedContentEndpoint(
                    loadContent: { original },
                    loadComments: { [] },
                    setLike: { _ in throw FieldTripTestError.expected },
                    createComment: { _ in throw FieldTripTestError.expected }
                ),
                selectionFeedback: {},
                successFeedback: {},
                errorFeedback: { errorFeedbackCount += 1 },
                errorMessage: { _ in "expected error" }
            )
        )

        await viewModel.load()
        await viewModel.toggleLike()

        #expect(viewModel.content == original)
        #expect(!viewModel.isUpdatingLike)
        #expect(errorFeedbackCount == 1)
        #expect(viewModel.toastMessage != nil)
    }

    @Test func commentsTrimToTheLimitAndRestoreTheDraftAfterFailure() async {
        let content = FieldTripPublishedContent(
            publication: FieldTripTestFixtures.publicationDetail()
        )
        var submittedBodies: [String] = []
        var shouldFail = false
        let viewModel = FieldTripPublishedContentViewModel(
            dependencies: FieldTripPublishedContentViewModel.Dependencies(
                endpoint: FieldTripPublishedContentEndpoint(
                    loadContent: { content },
                    loadComments: { [] },
                    setLike: { _ in
                        FieldTripPublishedContentLikeResult(
                            viewerHasLiked: true,
                            likeCount: 3,
                            commentCount: nil
                        )
                    },
                    createComment: { body in
                        submittedBodies.append(body)
                        if shouldFail {
                            throw FieldTripTestError.expected
                        }
                        return FieldTripPublishedContentCommentResult(
                            comment: FieldTripTestFixtures.comment(body: body),
                            commentCount: 2
                        )
                    }
                ),
                selectionFeedback: {},
                successFeedback: {},
                errorFeedback: {},
                errorMessage: { _ in "expected error" }
            )
        )
        await viewModel.load()

        viewModel.commentDraft = "   \(String(repeating: "x", count: 510))   "
        await viewModel.submitComment()

        #expect(submittedBodies.first?.count == 500)
        #expect(submittedBodies.first == String(repeating: "x", count: 500))
        #expect(viewModel.commentDraft.isEmpty)
        #expect(viewModel.comments.last?.body.count == 500)
        #expect(viewModel.content?.commentCount == 2)

        shouldFail = true
        viewModel.commentDraft = "  restore me  "
        await viewModel.submitComment()

        #expect(submittedBodies.last == "restore me")
        #expect(viewModel.commentDraft == "  restore me  ")
        #expect(viewModel.commentErrorMessage == "expected error")
        #expect(!viewModel.isSubmittingComment)
    }
}
