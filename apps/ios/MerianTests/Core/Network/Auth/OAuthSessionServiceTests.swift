import Foundation
@testable import Merian
import Supabase
import XCTest

@MainActor
final class OAuthSessionServiceTests: XCTestCase {
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
                throw OAuthSessionServiceTestError.expected
            }
        )

        do {
            _ = try await service.updateProfileMetadata(
                OAuthProfileMetadata(displayName: "Ada Lovelace")
            )
            XCTFail("Expected the SDK update failure")
        } catch OAuthSessionServiceTestError.expected {
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
        readSession: @escaping OAuthSessionService.ReadSessionOperation = {
            OAuthSessionServiceTests.session(
                userID: OAuthSessionServiceTests.readUserID,
                isAnonymous: true
            )
        },
        currentSession: @escaping OAuthSessionService.CurrentSessionOperation = {
            nil
        },
        linkIdentity: @escaping OAuthSessionService.LinkIdentityOperation = { _ in },
        installSession: @escaping OAuthSessionService.InstallSessionOperation = { _ in
            OAuthSessionServiceTests.session(
                userID: OAuthSessionServiceTests.currentUserID,
                isAnonymous: false
            )
        },
        updateProfile: @escaping OAuthSessionService.UpdateProfileOperation = { _ in
            OAuthSessionServiceTests.user(
                id: OAuthSessionServiceTests.currentUserID,
                isAnonymous: false
            )
        }
    ) -> OAuthSessionService {
        OAuthSessionService(
            readSession: readSession,
            currentSession: currentSession,
            linkIdentity: linkIdentity,
            installSession: installSession,
            updateProfile: updateProfile
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

private enum OAuthSessionServiceTestError: Error {
    case expected
}
