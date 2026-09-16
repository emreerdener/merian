import Foundation
@testable import Merian
import Supabase
import XCTest

@MainActor
final class LegacyPurchaseHandoffRemoteServiceTests: XCTestCase {
    func testInjectedOperationsPreserveTypedHandoffInputs() async throws {
        let handoff = PendingSignOutPurchaseHandoff(
            sourceUserId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            handoffId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            handoffSecret: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            expiresAt: "2026-09-14T00:10:00Z"
        )
        let preparation = LegacyPurchaseIdentityHandoffPreparation(
            handoffID: handoff.handoffId,
            handoffSecret: handoff.handoffSecret,
            expiresAt: handoff.expiresAt
        )
        var events: [String] = []
        let service = LegacyPurchaseHandoffRemoteService(
            prepare: {
                events.append("prepare")
                return preparation
            },
            bind: { received, destinationUserID in
                XCTAssertEqual(received, handoff)
                events.append("bind-\(destinationUserID)")
            },
            complete: { received in
                XCTAssertEqual(received, handoff)
                events.append("complete")
            },
            cancel: { received in
                XCTAssertEqual(received, handoff)
                events.append("cancel")
            },
            isTerminalProofError: { _ in true }
        )

        let prepared = try await service.prepare()
        XCTAssertEqual(prepared, preparation)
        try await service.bind(handoff, to: "destination")
        try await service.complete(handoff)
        try await service.cancel(handoff)
        XCTAssertTrue(service.isTerminalProofError(URLError(.timedOut)))
        XCTAssertEqual(
            events,
            ["prepare", "bind-destination", "complete", "cancel"]
        )
    }

    func testTerminalProofClassifierRejectsTransientAndUnknownFailures() {
        let expired = FunctionsError.httpError(
            code: 410,
            data: Data(#"{"code":"handoff_expired"}"#.utf8)
        )
        let invalid = FunctionsError.httpError(
            code: 404,
            data: Data(#"{"code":"handoff_invalid"}"#.utf8)
        )
        let pending = FunctionsError.httpError(
            code: 503,
            data: Data(#"{"code":"purchase_transfer_pending"}"#.utf8)
        )

        XCTAssertTrue(
            LegacyPurchaseHandoffRemoteService
                .isTerminalProofError(expired)
        )
        XCTAssertTrue(
            LegacyPurchaseHandoffRemoteService
                .isTerminalProofError(invalid)
        )
        XCTAssertFalse(
            LegacyPurchaseHandoffRemoteService
                .isTerminalProofError(pending)
        )
        XCTAssertFalse(
            LegacyPurchaseHandoffRemoteService
                .isTerminalProofError(URLError(.timedOut))
        )
    }
}
