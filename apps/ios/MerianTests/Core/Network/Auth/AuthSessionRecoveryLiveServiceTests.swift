import Foundation
@testable import Merian
import Supabase
import XCTest

@MainActor
final class AuthSessionRecoveryLiveServiceTests: XCTestCase {
    func testRefreshedAndLoadedSessionsProjectIdentityAndUser() async throws {
        let refreshed = Self.session(
            userID: Self.refreshedUserID,
            isAnonymous: false
        )
        let loaded = Self.session(
            userID: Self.loadedUserID,
            isAnonymous: true
        )
        var refreshCount = 0
        var loadCount = 0
        let service = Self.service(
            refreshSession: {
                refreshCount += 1
                return refreshed
            },
            readSession: {
                loadCount += 1
                return loaded
            }
        )

        let refreshedProjection = try await service.refreshSession()
        let loadedProjection = try await service.loadSession()

        XCTAssertEqual(refreshedProjection.user, refreshed.user)
        XCTAssertEqual(
            refreshedProjection.identity,
            AuthTransitionSession(
                userID: Self.refreshedUserID,
                isAnonymous: false
            )
        )
        XCTAssertEqual(loadedProjection.user, loaded.user)
        XCTAssertEqual(
            loadedProjection.identity,
            AuthTransitionSession(
                userID: Self.loadedUserID,
                isAnonymous: true
            )
        )
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(loadCount, 1)
    }

    func testLocalSignOutDelegatesExactlyOnce() async throws {
        var signOutCount = 0
        let service = Self.service(
            localSignOut: {
                signOutCount += 1
            }
        )

        try await service.signOutLocalSession()

        XCTAssertEqual(signOutCount, 1)
    }

    func testRefreshFailurePropagates() async {
        let service = Self.service(
            refreshSession: {
                throw AuthSessionRecoveryLiveServiceTestError.refresh
            }
        )

        do {
            _ = try await service.refreshSession()
            XCTFail("Expected the SDK refresh failure")
        } catch AuthSessionRecoveryLiveServiceTestError.refresh {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadFailurePropagates() async {
        let service = Self.service(
            readSession: {
                throw AuthSessionRecoveryLiveServiceTestError.load
            }
        )

        do {
            _ = try await service.loadSession()
            XCTFail("Expected the SDK session-read failure")
        } catch AuthSessionRecoveryLiveServiceTestError.load {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLocalSignOutFailurePropagates() async {
        let service = Self.service(
            localSignOut: {
                throw AuthSessionRecoveryLiveServiceTestError.signOut
            }
        )

        do {
            try await service.signOutLocalSession()
            XCTFail("Expected the local SDK sign-out failure")
        } catch AuthSessionRecoveryLiveServiceTestError.signOut {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static let refreshedUserID = UUID(
        uuidString: "44444444-4444-4444-8444-444444444444"
    )!
    private static let loadedUserID = UUID(
        uuidString: "55555555-5555-4555-8555-555555555555"
    )!

    private static func service(
        refreshSession: @escaping AuthSessionRecoveryLiveService
            .RefreshSessionOperation = {
                AuthSessionRecoveryLiveServiceTests.session(
                    userID:
                        AuthSessionRecoveryLiveServiceTests.refreshedUserID,
                    isAnonymous: false
                )
            },
        readSession: @escaping AuthSessionRecoveryLiveService
            .ReadSessionOperation = {
                AuthSessionRecoveryLiveServiceTests.session(
                    userID: AuthSessionRecoveryLiveServiceTests.loadedUserID,
                    isAnonymous: true
                )
            },
        localSignOut: @escaping AuthSessionRecoveryLiveService
            .LocalSignOutOperation = {}
    ) -> AuthSessionRecoveryLiveService {
        AuthSessionRecoveryLiveService(
            refreshSession: refreshSession,
            readSession: readSession,
            localSignOut: localSignOut
        )
    }

    private static func session(
        userID: UUID,
        isAnonymous: Bool
    ) -> Session {
        Session(
            accessToken: "test-access-token",
            tokenType: "bearer",
            expiresIn: 3_600,
            expiresAt: Date.distantFuture.timeIntervalSince1970,
            refreshToken: "test-refresh-token",
            user: User(
                id: userID,
                appMetadata: [:],
                userMetadata: [:],
                aud: "authenticated",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                isAnonymous: isAnonymous
            )
        )
    }
}

private enum AuthSessionRecoveryLiveServiceTestError: Error {
    case refresh
    case load
    case signOut
}
