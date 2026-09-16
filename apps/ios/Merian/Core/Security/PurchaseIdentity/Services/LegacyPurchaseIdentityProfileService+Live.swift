import Supabase

private struct LegacyPurchaseIdentityProfileDTO: Decodable {
    let email: String?
    let publicUsername: String?
    let publicAuthorName: String?
    let publicIdentitySource: String?
    let publicAvatarURL: String?

    private enum CodingKeys: String, CodingKey {
        case email
        case publicUsername = "public_username"
        case publicAuthorName = "public_author_name"
        case publicIdentitySource = "public_identity_source"
        case publicAvatarURL = "public_avatar_url"
    }

    var profile: LegacyPurchaseIdentityProfile {
        LegacyPurchaseIdentityProfile(
            email: email,
            publicUsername: publicUsername,
            publicAuthorName: publicAuthorName,
            publicIdentitySource: publicIdentitySource,
            publicAvatarURL: publicAvatarURL
        )
    }
}

extension LegacyPurchaseIdentityProfileService {
    static func live(client: SupabaseClient) -> Self {
        Self(fetch: { userID in
            let response: [LegacyPurchaseIdentityProfileDTO] = try await client
                .from("users")
                .select(
                    "email,public_username,public_author_name," +
                        "public_identity_source,public_avatar_url"
                )
                .eq("id", value: userID)
                .limit(1)
                .execute()
                .value
            return response.first?.profile
        })
    }
}
