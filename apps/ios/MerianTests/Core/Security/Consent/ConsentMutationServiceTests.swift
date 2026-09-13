import Foundation
@testable import Merian
import XCTest

@MainActor
final class ConsentMutationServiceTests: XCTestCase {
    func testConfirmationBuildsDeterministicLocalEvidence() throws {
        let store = FaultInjectingConsentLedgerStore()
        let repository = ConsentLedgerRepository(store: store)
        let occurredAt = Date(timeIntervalSince1970: 1_770_000_000)
        let ownerUserId = UUID(
            uuidString: "11111111-2222-4333-8444-555555555555"
        )!
        var identifiers = [
            UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
            UUID(uuidString: "10000000-0000-4000-8000-000000000002")!,
            UUID(uuidString: "10000000-0000-4000-8000-000000000003")!,
            UUID(uuidString: "10000000-0000-4000-8000-000000000004")!
        ]
        let service = ConsentMutationService(
            ledgerRepository: repository,
            dependencies: .init(
                now: { occurredAt },
                makeUUID: { identifiers.removeFirst() },
                appVersion: { "9.8.7" },
                appBuild: { "654" }
            )
        )
        var refreshCount = 0

        let result = try service.confirmRequiredConsent(
            analyticsEnabled: true,
            context: .init(
                ownerUserId: ownerUserId,
                requiresReapproval: false,
                reapprovalBasisUserId: nil,
                reapprovalAIStreamHeadId: nil
            ),
            refreshAnalyticsPermission: { refreshCount += 1 }
        )

        XCTAssertNil(result.resolvedReapprovalUserId)
        XCTAssertEqual(refreshCount, 0)
        XCTAssertTrue(identifiers.isEmpty)
        XCTAssertEqual(repository.ledger.activeUserId, ownerUserId)
        XCTAssertEqual(
            repository.ledger.adultEligibilityReceipts.map(\.id),
            [UUID(uuidString: "10000000-0000-4000-8000-000000000001")!]
        )
        XCTAssertEqual(
            repository.ledger.termsReceipts.map(\.id),
            [UUID(uuidString: "10000000-0000-4000-8000-000000000002")!]
        )
        XCTAssertEqual(
            repository.ledger.aiConsentEvents.map(\.id),
            [UUID(uuidString: "10000000-0000-4000-8000-000000000003")!]
        )
        XCTAssertEqual(
            repository.ledger.analyticsConsentEvents.map(\.id),
            [UUID(uuidString: "10000000-0000-4000-8000-000000000004")!]
        )
        XCTAssertEqual(
            repository.ledger.adultEligibilityReceipts.first?.confirmedAt,
            occurredAt
        )
        XCTAssertEqual(
            repository.ledger.termsReceipts.first?.appVersion,
            "9.8.7"
        )
        XCTAssertEqual(
            repository.ledger.aiConsentEvents.first?.appBuild,
            "654"
        )
        XCTAssertNil(
            repository.ledger.aiConsentEvents.first?.causalParentId
        )
    }

    func testAnalyticsWithdrawalClosesPermissionBeforeFailedLedgerWrite() throws {
        let store = FaultInjectingConsentLedgerStore()
        let repository = ConsentLedgerRepository(store: store)
        let ownerUserId = UUID(
            uuidString: "22222222-3333-4444-8555-666666666666"
        )!
        var identifiers = [
            UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
            UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
        ]
        let service = ConsentMutationService(
            ledgerRepository: repository,
            dependencies: .init(
                now: { Date(timeIntervalSince1970: 1_780_000_000) },
                makeUUID: { identifiers.removeFirst() },
                appVersion: { "1.0" },
                appBuild: { "1" }
            )
        )
        _ = try service.setAnalyticsEnabled(
            true,
            ownerUserId: ownerUserId,
            refreshAnalyticsPermission: {}
        )
        store.operations.removeAll()
        store.failLedgerWrites = true
        var permissionWasClosed = false

        XCTAssertThrowsError(
            try service.setAnalyticsEnabled(
                false,
                ownerUserId: ownerUserId,
                refreshAnalyticsPermission: {
                    permissionWasClosed =
                        repository.isAnalyticsWithdrawalInProgress
                }
            )
        )
        XCTAssertTrue(permissionWasClosed)
        XCTAssertTrue(repository.isAnalyticsWithdrawalInProgress)
        XCTAssertEqual(store.operations, ["saveIntent", "saveLedger"])
    }

    func testNoOpAnalyticsWithdrawalRestoresInProcessState() throws {
        let store = FaultInjectingConsentLedgerStore()
        let repository = ConsentLedgerRepository(store: store)
        let service = ConsentMutationService(
            ledgerRepository: repository,
            dependencies: .init(
                now: Date.init,
                makeUUID: UUID.init,
                appVersion: { "1.0" },
                appBuild: { "1" }
            )
        )
        var observedWithdrawalStates: [Bool] = []

        let result = try service.setAnalyticsEnabled(
            false,
            ownerUserId: nil,
            refreshAnalyticsPermission: {
                observedWithdrawalStates.append(
                    repository.isAnalyticsWithdrawalInProgress
                )
            }
        )

        XCTAssertEqual(result, .unchanged)
        XCTAssertEqual(observedWithdrawalStates, [true, false])
        XCTAssertFalse(repository.isAnalyticsWithdrawalInProgress)
        XCTAssertTrue(store.operations.isEmpty)
    }
}
