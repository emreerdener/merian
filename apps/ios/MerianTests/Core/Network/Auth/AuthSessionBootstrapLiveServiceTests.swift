import Foundation
@testable import Merian
import Supabase
import XCTest

@MainActor
final class AuthSessionBootstrapLiveServiceTests: XCTestCase {
    func testCurrentAndLoadedSessionsProjectIdentityAndExpiry() async throws {
        let current = Self.session(
            userID: Self.currentUserID,
            isAnonymous: false,
            expiresAt: Date.distantPast
        )
        let loaded = Self.session(
            userID: Self.loadedUserID,
            isAnonymous: true,
            expiresAt: Date.distantFuture
        )
        var loadCount = 0
        let service = Self.service(
            readSession: {
                loadCount += 1
                return loaded
            },
            currentSession: { current }
        )

        let currentProjection = try XCTUnwrap(service.currentSession())
        let loadedProjection = try await service.loadSession()

        XCTAssertEqual(currentProjection.user, current.user)
        XCTAssertEqual(
            currentProjection.identity,
            AuthTransitionSession(
                userID: Self.currentUserID,
                isAnonymous: false
            )
        )
        XCTAssertTrue(currentProjection.isExpired)
        XCTAssertEqual(loadedProjection.user, loaded.user)
        XCTAssertEqual(
            loadedProjection.identity,
            AuthTransitionSession(
                userID: Self.loadedUserID,
                isAnonymous: true
            )
        )
        XCTAssertFalse(loadedProjection.isExpired)
        XCTAssertEqual(loadCount, 1)
    }

    func testAnonymousCreationProjectsFreshIdentity() async throws {
        let anonymous = Self.session(
            userID: Self.anonymousUserID,
            isAnonymous: true,
            expiresAt: Date.distantPast
        )
        var creationCount = 0
        let service = Self.service(
            createAnonymousSession: {
                creationCount += 1
                return anonymous
            }
        )

        let projection = try await service.createAnonymousSession()

        XCTAssertEqual(projection.user, anonymous.user)
        XCTAssertEqual(
            projection.identity,
            AuthTransitionSession(
                userID: Self.anonymousUserID,
                isAnonymous: true
            )
        )
        XCTAssertFalse(projection.isExpired)
        XCTAssertEqual(creationCount, 1)
    }

    func testMissingSessionClassifierRecognizesSDKAndCompatibilityErrors() {
        let service = Self.service()

        XCTAssertTrue(service.isSessionMissingError(AuthError.sessionMissing))
        XCTAssertTrue(
            service.isSessionMissingError(
                AuthSessionBootstrapDescribedError(
                    description: "legacy sessionNotFound response"
                )
            )
        )
        XCTAssertTrue(
            service.isSessionMissingError(
                AuthSessionBootstrapDescribedError(
                    description: "legacy sessionMissing response"
                )
            )
        )
    }

    func testMissingSessionClassifierRejectsUnrelatedError() {
        let service = Self.service()

        XCTAssertFalse(
            service.isSessionMissingError(
                AuthSessionBootstrapDescribedError(
                    description: "network unavailable"
                )
            )
        )
    }

    func testLoadedSessionPreservesSDKFailure() async {
        let service = Self.service(
            readSession: {
                throw AuthSessionBootstrapLiveServiceTestError.expected
            }
        )

        do {
            _ = try await service.loadSession()
            XCTFail("Expected the SDK session failure")
        } catch AuthSessionBootstrapLiveServiceTestError.expected {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static let currentUserID = UUID(
        uuidString: "11111111-1111-4111-8111-111111111111"
    )!
    private static let loadedUserID = UUID(
        uuidString: "22222222-2222-4222-8222-222222222222"
    )!
    private static let anonymousUserID = UUID(
        uuidString: "33333333-3333-4333-8333-333333333333"
    )!

    private static func service(
        readSession: @escaping AuthSessionBootstrapLiveService
            .ReadSessionOperation = {
                AuthSessionBootstrapLiveServiceTests.session(
                    userID: AuthSessionBootstrapLiveServiceTests.loadedUserID,
                    isAnonymous: false,
                    expiresAt: Date.distantFuture
                )
            },
        currentSession: @escaping AuthSessionBootstrapLiveService
            .CurrentSessionOperation = { nil },
        createAnonymousSession: @escaping AuthSessionBootstrapLiveService
            .CreateAnonymousSessionOperation = {
                AuthSessionBootstrapLiveServiceTests.session(
                    userID:
                        AuthSessionBootstrapLiveServiceTests.anonymousUserID,
                    isAnonymous: true,
                    expiresAt: Date.distantFuture
                )
            }
    ) -> AuthSessionBootstrapLiveService {
        AuthSessionBootstrapLiveService(
            readSession: readSession,
            currentSession: currentSession,
            createAnonymousSession: createAnonymousSession
        )
    }

    private static func session(
        userID: UUID,
        isAnonymous: Bool,
        expiresAt: Date
    ) -> Session {
        Session(
            accessToken: "test-access-token",
            tokenType: "bearer",
            expiresIn: 3_600,
            expiresAt: expiresAt.timeIntervalSince1970,
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

private struct AuthSessionBootstrapDescribedError:
    CustomStringConvertible, Error {
    let description: String
}

private enum AuthSessionBootstrapLiveServiceTestError: Error {
    case expected
}
