import Foundation
@testable import Merian
import Supabase
import XCTest

@MainActor
final class GhostProfileMergeRemoteServiceTests: XCTestCase {
    func testTypedOperationsForwardExactProviderAndHandoffValues() async throws {
        var preparedProvider: String?
        var preparedSubject: String?
        var completedHandoff: PendingGhostProfileMerge?
        var didRefreshIdentity = false
        let pending = makeHandoff()
        let expected = GhostProfileMergePreparation(
            handoffID: pending.handoffId,
            handoffSecret: pending.handoffSecret,
            expiresAt: pending.expiresAt
        )
        let service = GhostProfileMergeRemoteService(
            prepare: { provider, subject in
                preparedProvider = provider
                preparedSubject = subject
                return expected
            },
            complete: { handoff in
                completedHandoff = handoff
            },
            refreshIdentity: {
                didRefreshIdentity = true
            },
            requiresProviderBoundMerge: { _ in true },
            isTerminalHandoffError: { _ in true }
        )

        let preparation = try await service.prepare(
            provider: pending.provider,
            providerSubject: pending.providerSubject
        )
        try await service.complete(pending)
        try await service.refreshIdentity()

        XCTAssertEqual(preparation, expected)
        XCTAssertEqual(preparedProvider, pending.provider)
        XCTAssertEqual(preparedSubject, pending.providerSubject)
        XCTAssertEqual(completedHandoff, pending)
        XCTAssertTrue(didRefreshIdentity)
        XCTAssertTrue(
            service.requiresProviderBoundMerge(after: URLError(.unknown))
        )
        XCTAssertTrue(service.isTerminalHandoffError(URLError(.unknown)))
    }

    func testProviderBoundMergeFallbackOnlyAcceptsIdentityConflict() {
        let response = HTTPURLResponse(
            url: URL(string: "https://auth.example.test")!,
            statusCode: 422,
            httpVersion: nil,
            headerFields: nil
        )!
        let identityConflict = AuthError.api(
            message: "Identity already linked",
            errorCode: .identityAlreadyExists,
            underlyingData: Data(),
            underlyingResponse: response
        )
        let transientFailure = AuthError.api(
            message: "Request timed out",
            errorCode: .requestTimeout,
            underlyingData: Data(),
            underlyingResponse: response
        )

        XCTAssertTrue(
            GhostProfileMergeRemoteService.requiresProviderBoundMerge(
                after: identityConflict
            )
        )
        XCTAssertFalse(
            GhostProfileMergeRemoteService.requiresProviderBoundMerge(
                after: transientFailure
            )
        )
        XCTAssertFalse(
            GhostProfileMergeRemoteService.requiresProviderBoundMerge(
                after: URLError(.notConnectedToInternet)
            )
        )
    }

    func testPendingMergeProofIsDiscardedOnlyForTerminalServerCodes() {
        let cases: [(Error, Bool)] = [
            (
                FunctionsError.httpError(
                    code: 410,
                    data: Data(#"{"code":"handoff_expired"}"#.utf8)
                ),
                true
            ),
            (
                FunctionsError.httpError(
                    code: 404,
                    data: Data(#"{"code":"handoff_invalid"}"#.utf8)
                ),
                true
            ),
            (
                FunctionsError.httpError(
                    code: 403,
                    data: Data(#"{"code":"handoff_forbidden"}"#.utf8)
                ),
                false
            ),
            (
                FunctionsError.httpError(
                    code: 503,
                    data: Data(#"{"code":"auth_cleanup_pending"}"#.utf8)
                ),
                false
            ),
            (
                FunctionsError.httpError(
                    code: 503,
                    data: Data(
                        #"{"code":"merge_temporarily_unavailable"}"#.utf8
                    )
                ),
                false
            ),
            (URLError(.timedOut), false)
        ]

        for (error, expected) in cases {
            XCTAssertEqual(
                GhostProfileMergeRemoteService.isTerminalHandoffError(error),
                expected
            )
        }
    }

    private func makeHandoff() -> PendingGhostProfileMerge {
        PendingGhostProfileMerge(
            ghostUserId:
                "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA".lowercased(),
            provider: "google",
            providerSubject: "provider-subject",
            handoffId: "11111111-1111-1111-1111-111111111111",
            handoffSecret:
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            expiresAt: "2026-09-14T00:10:00Z"
        )
    }
}
