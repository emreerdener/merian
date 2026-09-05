import Foundation
@testable import Merian
import Supabase
import XCTest

final class GhostMergeEndpointErrorTests: XCTestCase {
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
                SupabaseManager.shouldDiscardPendingGhostProfileMerge(
                    after: error
                ),
                expected
            )
        }
    }
}
