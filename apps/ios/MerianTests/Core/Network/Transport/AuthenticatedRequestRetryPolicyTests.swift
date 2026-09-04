import Foundation
import Testing

@testable import Merian

@Suite("Authenticated Request Retry Policy")
struct AuthenticatedRequestRetryPolicyTests {
    @Test func authenticatedRetryChainNeverAdoptsReplacementAccount() {
        let sourceUserID = UUID()
        let replacementUserID = UUID()

        let initiallyBound = AuthenticatedRequestRetryPolicy.boundUserID(
            explicitUserID: nil,
            initiatingUserID: sourceUserID
        )
        let recursiveRetry = AuthenticatedRequestRetryPolicy.boundUserID(
            explicitUserID: initiallyBound,
            initiatingUserID: replacementUserID
        )

        #expect(initiallyBound == sourceUserID)
        #expect(recursiveRetry == sourceUserID)
        #expect(recursiveRetry != replacementUserID)
    }

    @Test func testUnauthorizedRecoveryOnlyRegeneratesAuthoritativelyMissingGuestSessions() {
        #expect(AuthenticatedRequestRetryPolicy
            .shouldRegenerateSessionAfterUnauthorized(
                responseProvesMissingSession: true,
                hasAuthenticatedOAuth: false,
                isGuestUser: true,
                purchaseIdentityHandoffPending: false
            ))
        #expect(!AuthenticatedRequestRetryPolicy
            .shouldRegenerateSessionAfterUnauthorized(
                responseProvesMissingSession: false,
                hasAuthenticatedOAuth: false,
                isGuestUser: true,
                purchaseIdentityHandoffPending: false
            ))
        #expect(!AuthenticatedRequestRetryPolicy
            .shouldRegenerateSessionAfterUnauthorized(
                responseProvesMissingSession: true,
                hasAuthenticatedOAuth: true,
                isGuestUser: true,
                purchaseIdentityHandoffPending: false
            ))
        #expect(!AuthenticatedRequestRetryPolicy
            .shouldRegenerateSessionAfterUnauthorized(
                responseProvesMissingSession: true,
                hasAuthenticatedOAuth: false,
                isGuestUser: false,
                purchaseIdentityHandoffPending: false
            ))
        #expect(!AuthenticatedRequestRetryPolicy
            .shouldRegenerateSessionAfterUnauthorized(
                responseProvesMissingSession: false,
                hasAuthenticatedOAuth: true,
                isGuestUser: false,
                purchaseIdentityHandoffPending: false
            ))
        #expect(!AuthenticatedRequestRetryPolicy
            .shouldRegenerateSessionAfterUnauthorized(
                responseProvesMissingSession: true,
                hasAuthenticatedOAuth: false,
                isGuestUser: true,
                purchaseIdentityHandoffPending: true
            ))
    }

    @Test func testUnauthorizedRefreshStaysInsideItsAuthTransitionOwner() {
        let owner = AuthTransitionToken(
            id: UUID(),
            kind: .accountDeletion
        )

        #expect(
            AuthenticatedRequestRetryPolicy.unauthorizedRefreshTarget(
                authTransitionOwner: owner
            ) == .transitionOwned(owner)
        )
        #expect(
            AuthenticatedRequestRetryPolicy.unauthorizedRefreshTarget(
                authTransitionOwner: nil
            ) == .ordinary
        )
    }

    @Test func testAmbiguousFailureReplayIsLimitedToReadsAndIdempotentRequests() throws {
        let baseURL = try #require(
            URL(string: "https://example.supabase.co/functions/v1/")
        )
        let readURL = baseURL.appendingPathComponent("get-explore-feed")
        let commentURL = baseURL.appendingPathComponent(
            "create-explore-comment"
        )
        let reactionURL = baseURL.appendingPathComponent(
            "toggle-explore-comment-reaction"
        )
        let feedbackURL = baseURL.appendingPathComponent(
            "submit-feedback-survey"
        )
        let uploadURL = baseURL.appendingPathComponent("generate-upload-urls")
        let dictionaryChatURL = baseURL.appendingPathComponent(
            "species-dictionary-chat"
        )
        let idempotencyKey = "019fa6ef-4fab-7d42-84d8-74dc8b1b5bb0"

        #expect(AuthenticatedRequestRetryPolicy.canReplayAfterAmbiguousFailure(
            url: readURL,
            method: "POST",
            idempotencyKey: nil
        ))
        for url in [commentURL, reactionURL, feedbackURL, uploadURL] {
            #expect(!AuthenticatedRequestRetryPolicy
                .canReplayAfterAmbiguousFailure(
                    url: url,
                    method: "POST",
                    idempotencyKey: nil
                ))
        }
        #expect(!AuthenticatedRequestRetryPolicy.canReplayAfterAmbiguousFailure(
            url: commentURL,
            method: "POST",
            idempotencyKey: idempotencyKey
        ))
        #expect(AuthenticatedRequestRetryPolicy.canReplayAfterAmbiguousFailure(
            url: baseURL.appendingPathComponent("identify-multimodal"),
            method: "POST",
            idempotencyKey: idempotencyKey
        ))
        #expect(!AuthenticatedRequestRetryPolicy.canReplayAfterAmbiguousFailure(
            url: dictionaryChatURL,
            method: "POST",
            idempotencyKey: nil
        ))
        #expect(AuthenticatedRequestRetryPolicy.canReplayAfterAmbiguousFailure(
            url: dictionaryChatURL,
            method: "POST",
            idempotencyKey: idempotencyKey
        ))
        #expect(AuthenticatedRequestRetryPolicy.canReplayAfterAmbiguousFailure(
            url: commentURL,
            method: "GET",
            idempotencyKey: nil
        ))
    }
}
