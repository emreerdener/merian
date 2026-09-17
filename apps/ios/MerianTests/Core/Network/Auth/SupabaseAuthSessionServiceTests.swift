import Foundation
@testable import Merian
import Supabase
import XCTest

@MainActor
final class SupabaseAuthSessionServiceTests: XCTestCase {
    func testReadAndCurrentSessionExposeInjectedSDKState() async throws {
        let readSession = Self.session(
            userID: Self.readUserID,
            isAnonymous: true
        )
        let currentSession = Self.session(
            userID: Self.currentUserID,
            isAnonymous: false
        )
        var readCount = 0
        let service = Self.service(
            readSession: {
                readCount += 1
                return readSession
            },
            currentSession: { currentSession }
        )

        let loadedSession = try await service.readSession()

        XCTAssertEqual(loadedSession, readSession)
        XCTAssertEqual(service.currentSession(), currentSession)
        XCTAssertEqual(readCount, 1)
    }

    func testAppleLinkMapsExactOpenIDCredentials() async throws {
        var receivedCredentials: OpenIDConnectCredentials?
        let service = Self.service(
            linkIdentity: {
                receivedCredentials = $0
            }
        )

        try await service.linkIdentity(
            using: OAuthSignInCredentials(
                provider: .apple,
                idToken: "apple-identity-token",
                accessToken: nil,
                nonce: "apple-nonce"
            )
        )

        XCTAssertEqual(
            receivedCredentials,
            OpenIDConnectCredentials(
                provider: .apple,
                idToken: "apple-identity-token",
                accessToken: nil,
                nonce: "apple-nonce"
            )
        )
    }

    func testGoogleInstallMapsCredentialsAndReturnsSDKSession() async throws {
        let installedSession = Self.session(
            userID: Self.currentUserID,
            isAnonymous: false
        )
        var receivedCredentials: OpenIDConnectCredentials?
        let service = Self.service(
            installSession: {
                receivedCredentials = $0
                return installedSession
            }
        )

        let result = try await service.installSession(
            using: OAuthSignInCredentials(
                provider: .google,
                idToken: "google-identity-token",
                accessToken: "google-access-token",
                nonce: nil
            )
        )

        XCTAssertEqual(result, installedSession)
        XCTAssertEqual(
            receivedCredentials,
            OpenIDConnectCredentials(
                provider: .google,
                idToken: "google-identity-token",
                accessToken: "google-access-token",
                nonce: nil
            )
        )
    }

    func testCallbackInstallForwardsExactURLAndReturnsSDKSession() async throws {
        let callbackURL = URL(
            string: "merian://auth/callback?code=test-code"
        )!
        let installedSession = Self.session(
            userID: Self.currentUserID,
            isAnonymous: false
        )
        var receivedURLs: [URL] = []
        let service = Self.service(
            installCallbackSession: { url in
                receivedURLs.append(url)
                return installedSession
            }
        )

        let result = try await service.installCallbackSession(
            from: callbackURL
        )

        XCTAssertEqual(result, installedSession)
        XCTAssertEqual(receivedURLs, [callbackURL])
    }

    func testCallbackInstallPreservesSDKFailure() async {
        let service = Self.service(
            installCallbackSession: { _ in
                throw SupabaseAuthSessionServiceTestError.expected
            }
        )

        do {
            _ = try await service.installCallbackSession(
                from: URL(string: "merian://auth/callback")!
            )
            XCTFail("Expected the SDK callback failure")
        } catch SupabaseAuthSessionServiceTestError.expected {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSessionProjectionPreservesIdentityAndAnonymity() {
        let session = Self.session(
            userID: Self.readUserID,
            isAnonymous: true
        )
        let service = Self.service()

        let projectedSession = service.signInSession(from: session)

        XCTAssertEqual(projectedSession.userID, Self.readUserID)
        XCTAssertTrue(projectedSession.isAnonymous)
    }

    func testMetadataUpdateBuildsCanonicalAliases() async throws {
        let updatedUser = Self.user(
            id: Self.currentUserID,
            isAnonymous: false
        )
        var receivedAttributes: UserAttributes?
        let service = Self.service(
            updateProfile: {
                receivedAttributes = $0
                return updatedUser
            }
        )

        let result = try await service.updateProfileMetadata(
            OAuthProfileMetadata(
                displayName: " Ada Lovelace ",
                givenName: " Ada ",
                familyName: " Lovelace ",
                avatarURL: " https://example.test/avatar "
            )
        )

        XCTAssertEqual(result, updatedUser)
        XCTAssertEqual(
            receivedAttributes?.data,
            [
                "full_name": .string("Ada Lovelace"),
                "name": .string("Ada Lovelace"),
                "given_name": .string("Ada"),
                "family_name": .string("Lovelace"),
                "avatar_url": .string("https://example.test/avatar"),
                "picture": .string("https://example.test/avatar")
            ]
        )
    }

    func testEmptyMetadataSkipsSDKUpdate() async throws {
        var updateCount = 0
        let service = Self.service(
            updateProfile: { _ in
                updateCount += 1
                return Self.user(
                    id: Self.currentUserID,
                    isAnonymous: false
                )
            }
        )

        let result = try await service.updateProfileMetadata(
            OAuthProfileMetadata()
        )

        XCTAssertNil(result)
        XCTAssertEqual(updateCount, 0)
    }

    func testMetadataUpdatePreservesSDKFailure() async {
        let service = Self.service(
            updateProfile: { _ in
                throw SupabaseAuthSessionServiceTestError.expected
            }
        )

        do {
            _ = try await service.updateProfileMetadata(
                OAuthProfileMetadata(displayName: "Ada Lovelace")
            )
            XCTFail("Expected the SDK update failure")
        } catch SupabaseAuthSessionServiceTestError.expected {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRefreshedAndLoadedSessionsProjectIdentityAndUser() async throws {
        let refreshed = Self.session(
            userID: Self.currentUserID,
            isAnonymous: false
        )
        let loaded = Self.session(
            userID: Self.readUserID,
            isAnonymous: true
        )
        var refreshCount = 0
        var loadCount = 0
        let service = Self.service(
            readSession: {
                loadCount += 1
                return loaded
            },
            refreshSession: {
                refreshCount += 1
                return refreshed
            }
        )

        let refreshedProjection = try await service
            .refreshRecoverySession()
        let loadedProjection = try await service.loadRecoverySession()

        XCTAssertEqual(refreshedProjection.user, refreshed.user)
        XCTAssertEqual(
            refreshedProjection.identity,
            AuthTransitionSession(
                userID: Self.currentUserID,
                isAnonymous: false
            )
        )
        XCTAssertEqual(loadedProjection.user, loaded.user)
        XCTAssertEqual(
            loadedProjection.identity,
            AuthTransitionSession(
                userID: Self.readUserID,
                isAnonymous: true
            )
        )
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(loadCount, 1)
    }

    func testRefreshFailurePropagates() async {
        let service = Self.service(
            refreshSession: {
                throw SupabaseAuthSessionServiceTestError.refresh
            }
        )
        do {
            _ = try await service.refreshRecoverySession()
            XCTFail("Expected the SDK refresh failure")
        } catch SupabaseAuthSessionServiceTestError.refresh {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadFailurePropagates() async {
        let service = Self.service(
            readSession: {
                throw SupabaseAuthSessionServiceTestError.load
            }
        )
        do {
            _ = try await service.loadRecoverySession()
            XCTFail("Expected the SDK session-read failure")
        } catch SupabaseAuthSessionServiceTestError.load {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSignOutDelegatesExactlyOnce() async throws {
        var signOutCount = 0
        let service = Self.service(
            signOutLocal: {
                signOutCount += 1
            }
        )

        try await service.signOutLocal()

        XCTAssertEqual(signOutCount, 1)
    }

    func testSignOutFailurePropagates() async {
        let service = Self.service(
            signOutLocal: {
                throw SupabaseAuthSessionServiceTestError.signOut
            }
        )

        do {
            try await service.signOutLocal()
            XCTFail("Expected the local SDK sign-out failure")
        } catch SupabaseAuthSessionServiceTestError.signOut {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static let readUserID = UUID(
        uuidString: "11111111-1111-4111-8111-111111111111"
    )!
    private static let currentUserID = UUID(
        uuidString: "22222222-2222-4222-8222-222222222222"
    )!

    private static func service(
        readSession: @escaping @MainActor () async throws -> Session = {
            SupabaseAuthSessionServiceTests.session(
                userID: SupabaseAuthSessionServiceTests.readUserID,
                isAnonymous: true
            )
        },
        currentSession: @escaping @MainActor () -> Session? = {
            nil
        },
        refreshSession: @escaping @MainActor () async throws -> Session = {
            SupabaseAuthSessionServiceTests.session(
                userID: SupabaseAuthSessionServiceTests.currentUserID,
                isAnonymous: false
            )
        },
        signOutLocal: @escaping @MainActor () async throws -> Void = {},
        linkIdentity: @escaping @MainActor (
            OpenIDConnectCredentials
        ) async throws -> Void = { _ in },
        installSession: @escaping @MainActor (
            OpenIDConnectCredentials
        ) async throws -> Session = { _ in
            SupabaseAuthSessionServiceTests.session(
                userID: SupabaseAuthSessionServiceTests.currentUserID,
                isAnonymous: false
            )
        },
        installCallbackSession: @escaping @MainActor (
            URL
        ) async throws -> Session = { _ in
                SupabaseAuthSessionServiceTests.session(
                    userID: SupabaseAuthSessionServiceTests.currentUserID,
                    isAnonymous: false
                )
            },
        updateProfile: @escaping @MainActor (
            UserAttributes
        ) async throws -> User = { _ in
            SupabaseAuthSessionServiceTests.user(
                id: SupabaseAuthSessionServiceTests.currentUserID,
                isAnonymous: false
            )
        }
    ) -> SupabaseAuthSessionService {
        SupabaseAuthSessionService(
            operations: SupabaseAuthSessionOperations(
                readSession: readSession,
                currentSession: currentSession,
                refreshSession: refreshSession,
                signOutLocal: signOutLocal,
                linkIdentity: linkIdentity,
                installSession: installSession,
                installCallbackSession: installCallbackSession,
                updateProfile: updateProfile
            )
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
            user: user(id: userID, isAnonymous: isAnonymous)
        )
    }

    private static func user(id: UUID, isAnonymous: Bool) -> User {
        User(
            id: id,
            appMetadata: [:],
            userMetadata: [:],
            aud: "authenticated",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isAnonymous: isAnonymous
        )
    }
}

private enum SupabaseAuthSessionServiceTestError: Error {
    case expected
    case refresh
    case load
    case signOut
}
