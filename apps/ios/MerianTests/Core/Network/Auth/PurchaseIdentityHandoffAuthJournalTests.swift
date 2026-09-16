import Foundation
@testable import Merian
import Testing

@Suite("Purchase Identity Handoff Auth Journal")
@MainActor
struct PurchaseIdentityHandoffAuthJournalTests {
    private enum StubError: Error {
        case unavailable
    }

    @Test func malformedLegacyLoadMapsToEstablishedAuthError() throws {
        let journal = makeJournal(
            loadData: { key in
                guard key == KeychainKeys.pendingSignOutPurchaseHandoff else {
                    return nil
                }
                return Data("malformed".utf8)
            }
        )

        do {
            _ = try journal.loadLegacyHandoff()
            Issue.record("Expected the established legacy persistence error")
        } catch SupabaseAuthTransitionError
            .signOutPurchaseHandoffPersistenceFailed {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func failedStablePersistenceMapsToEstablishedAuthError() {
        let journal = makeJournal(persistData: { _, _, _ in false })
        let rotation = ServerPrincipalRotation(
            protocolVersion: 3,
            localState: .preparing,
            rotationId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            rotationSecret: String(repeating: "r", count: 43),
            sourceUserId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            purchasePrincipalId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            revenueCatAppUserId: "MERIAN_PP_test",
            bindingGeneration: 2,
            installationCapabilityFingerprint: String(
                repeating: "f",
                count: 64
            ),
            startedAt: "2026-09-15T12:00:00Z",
            expiresAt: nil
        )

        do {
            try journal.persistStableRotation(rotation)
            Issue.record("Expected the established stable persistence error")
        } catch SupabaseAuthTransitionError
            .purchasePrincipalRotationPersistenceFailed {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func secureClearFailurePreservesUnderlyingDiagnostic() {
        let journal = makeJournal(
            removeDataVerified: { _ in throw StubError.unavailable }
        )

        #expect(throws: StubError.self) {
            try journal.clearLegacyHandoff()
        }
        #expect(throws: StubError.self) {
            try journal.clearStableRotation()
        }
    }

    private func makeJournal(
        loadData: @escaping (String) throws -> Data? = { _ in nil },
        persistData: @escaping (
            Data,
            String,
            KeychainManager.Accessibility
        ) -> Bool = { _, _, _ in true },
        removeDataVerified: @escaping (String) throws -> Void = { _ in }
    ) -> PurchaseIdentityHandoffAuthJournal {
        PurchaseIdentityHandoffAuthJournal(
            store: PurchaseIdentityHandoffStore(
                dependencies: .init(
                    loadData: loadData,
                    persistData: persistData,
                    removeDataVerified: removeDataVerified
                )
            )
        )
    }
}
