import Foundation

/// Public profile field updates and username availability. Normalization,
/// profile refresh, persistence, and avatar upload orchestration stay outside.
extension MerianNetworkClient {
    func updatePublicUsername(_ username: String) async throws -> PublicUsernameUpdateResponse {
        try await performAuthenticatedJSONPost(
            function: "update-public-username", payload: ["username": username], responseType: PublicUsernameUpdateResponse.self
        )
    }

    func updatePublicDisplayName(_ displayName: String) async throws -> PublicDisplayNameUpdateResponse {
        try await performAuthenticatedJSONPost(
            function: "update-public-display-name", payload: ["display_name": displayName], responseType: PublicDisplayNameUpdateResponse.self
        )
    }

    func updatePublicAvatar(r2ObjectKey: String, mimeType: String) async throws -> PublicAvatarUpdateResponse {
        let payload: [String: Any] = [
            "r2_object_key": r2ObjectKey,
            "mime_type": mimeType
        ]
        return try await performAuthenticatedJSONPost(
            function: "update-public-avatar", payload: payload, responseType: PublicAvatarUpdateResponse.self
        )
    }

    func checkPublicUsernameAvailability(_ username: String) async throws -> PublicUsernameAvailabilityResponse {
        try await performAuthenticatedJSONPost(
            function: "check-public-username", payload: ["username": username], responseType: PublicUsernameAvailabilityResponse.self
        )
    }
}
