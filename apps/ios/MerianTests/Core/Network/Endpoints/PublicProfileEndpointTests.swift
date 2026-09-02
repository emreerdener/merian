import Foundation
import Testing

@testable import Merian

@Suite("Public Profile Endpoints")
@MainActor
struct PublicProfileEndpointTests {
    private typealias RequestCase = NotificationAndPublicProfileEndpointRequestCase

    @Test func requestInventoryKeepsTheFourPublicProfileOperationsSeparate() {
        #expect(RequestCase.publicProfile.count == 16)
        #expect(RequestCase.publicProfileOperations.count == 4)
        #expect(Set(RequestCase.publicProfileOperations.map(\.function)) == [
            "update-public-username", "update-public-display-name", "update-public-avatar", "check-public-username"
        ])
    }

    @Test(arguments: NotificationAndPublicProfileEndpointRequestCase.publicProfile)
    func requestMappingRemainsStable(_ testCase: NotificationAndPublicProfileEndpointRequestCase) async throws {
        try await testCase.withResponse { client in
            try await testCase.invoke(client)
        }
    }

    // Rehomed endpoint regressions retain their names and use scoped clients.
    @Test func testUpdatePublicAvatarConstructsPayloadAndParsesResponse() async throws {
        try await RequestCase.avatar.withResponse { client in
            let response = try await client.updatePublicAvatar(
                r2ObjectKey: "staging/test-user/avatar.webp", mimeType: "image/webp"
            )
            #expect(response.avatarUrl == "https://media.example.test/avatars/avatar.webp")
        }
    }

    @Test func testUpdatePublicDisplayNameConstructsPayloadAndParsesResponse() async throws {
        try await RequestCase.displayName.withResponse { client in
            let response = try await client.updatePublicDisplayName("Test observer")
            #expect(response.displayName == "Test server label")
        }
    }

    @Test func testClearPublicDisplayNameSendsEmptyValueAndParsesAliasFallback() async throws {
        try await RequestCase.clearedDisplayName.withResponse { client in
            let response = try await client.updatePublicDisplayName("")
            #expect(response.displayName == "test_alias_23")
        }
    }

    @Test(arguments: ["test_normalized", "", " @RawServer "])
    func usernameUsesTheServerProjectionWithoutNormalization(_ username: String) async throws {
        try await RequestCase.username.withResponse(#"{"username":"\#(username)"}"#) { client in
            let response = try await client.updatePublicUsername(" @Test.Handle ")
            #expect(response.username == username)
        }
    }

    @Test func profileResponsesDoNotAcquireNewSuccessOrURLValidation() async throws {
        try await RequestCase.displayName.withResponse(#"{"success":false,"display_name":"  Test server  "}"#) { client in
            let response = try await client.updatePublicDisplayName("Test observer")
            #expect(response.displayName == "  Test server  ")
        }
        // The endpoint returns a string DTO; image admission remains a separate
        // boundary. This fixture is never used for an image or network request.
        try await RequestCase.avatar.withResponse(#"{"success":false,"avatar_url":"not-a-url"}"#) { client in
            let response = try await client.updatePublicAvatar(
                r2ObjectKey: "staging/test-user/avatar.webp", mimeType: "image/webp"
            )
            #expect(response.avatarUrl == "not-a-url")
        }
    }

    @Test(arguments: [true, false], ["omitted", "null", "message", "empty"])
    func availabilityKeepsFalseAndOptionalInlineErrors(available: Bool, errorCase: String) async throws {
        let errorJSON: String
        let expectedError: String?
        switch errorCase {
        case "omitted":
            errorJSON = ""
            expectedError = nil
        case "null":
            errorJSON = #","error":null"#
            expectedError = nil
        case "message":
            errorJSON = #","error":"Test handle unavailable""#
            expectedError = "Test handle unavailable"
        default:
            errorJSON = #","error":"""#
            expectedError = ""
        }
        try await RequestCase.usernameAvailability.withResponse(
            #"{"available":\#(available),"username":"test_server"\#(errorJSON)}"#
        ) { client in
            let response = try await client.checkPublicUsernameAvailability(" @Test.Handle ")
            #expect(response.available == available && response.username == "test_server")
            #expect(response.error == expectedError)
        }
    }
}
