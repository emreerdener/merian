import Observation
import SwiftUI

enum SignOutPresentationPolicy {
    static func incompleteMessage(isAnonymousSession: Bool) -> String {
        if isAnonymousSession {
            return "You're signed out. Purchase access is still syncing. Use Finish sign out on your profile to retry."
        }
        return "Naturebook couldn't sign you out. Check your connection and try again."
    }
}

struct ProfileSocialStats: Equatable {
    let followerCount: Int
    let followingCount: Int
    let visiblePublishedPostCount: Int
    let publicationIntentCount: Int
    let recoveryNeededPostCount: Int
    let degradedPostCount: Int
    let quarantinedPostCount: Int
}

struct PublicProfileIdentity: Decodable, Equatable {
    let publicUsername: String
    let publicAuthorName: String
    let publicIdentitySource: String
    let publicAvatarUrl: String?

    private enum CodingKeys: String, CodingKey {
        case publicUsername = "public_username"
        case publicAuthorName = "public_author_name"
        case publicIdentitySource = "public_identity_source"
        case publicAvatarUrl = "public_avatar_url"
    }
}

private struct PublicUsernameErrorResponse: Decodable {
    let error: String
}

/// An isolated ViewModel dedicated exclusively to managing asynchronous Cloud/Network boundaries (Supabase REST API).
/// Note: Massive Offline hardware calculations (SwiftData/SQLite arrays) are deliberately FIREWALLED completely out of this class
/// and routed into `@ModelActor` structs natively instead to avoid locking up `@MainActor` thread resources linearly!
@Observable
@MainActor
final class ProfileViewModel {
    // A state that instantly triggers SwiftUI View layout `.sheet` redraws dynamically 
    // the very millisecond the PostgreSQL network call physically returns data!
    var defaultGeoprivacy = "open"
    var socialStats: ProfileSocialStats?
    var isLoadingSocialStats = false
    var publicUsername: String?
    var publicAuthorName: String?
    var publicIdentitySource: String?
    var publicAvatarUrl: String?
    var isLoadingPublicIdentity = false
    var usernameUpdateErrorMessage: String?
    var displayNameUpdateErrorMessage: String?
    var avatarUpdateErrorMessage: String?
    var isUpdatingAvatar = false
    
    let supabase = SupabaseManager.shared
    
    // MARK: - Auth & Profile State Map
    var isGuestUser: Bool {
        supabase.isGuestUser
    }

    var currentUserId: String? {
        supabase.currentUser?.id.uuidString
    }
    
    var userName: String? {
        supabase.currentUser?.userMetadata["full_name"]?.stringValue ?? supabase.currentUser?.userMetadata["name"]?.stringValue
    }
    
    var userEmail: String? {
        supabase.currentUser?.email
    }
    
    var userAvatarURL: URL? {
        if let publicAvatarUrl,
           let url = SecureTransportPolicy.httpsURL(from: publicAvatarUrl) {
            return url
        }
        if let avatarStr = supabase.currentUser?.userMetadata["avatar_url"]?.stringValue ?? supabase.currentUser?.userMetadata["picture"]?.stringValue,
           let url = SecureTransportPolicy.httpsURL(from: avatarStr) {
            return url
        }
        return nil
    }

    var publicUsernameDisplayName: String? {
        guard let publicUsername, !publicUsername.isEmpty else { return nil }
        return "@\(publicUsername)"
    }

    var displayName: String {
        if publicIdentitySource == "display_name",
           let publicAuthorName,
           !publicAuthorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return publicAuthorName
        }
        if isGuestUser {
            if publicIdentitySource == "alias",
               let publicAuthorName,
               !publicAuthorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return publicAuthorName
            }
            // Provider-derived names remain private for anonymous accounts.
            // Explicit public names remain above.
            return "Explorer"
        }
        return userName ?? publicAuthorName ?? "Explorer"
    }
    
    // MARK: - Auth Flow Actions
    func signInWithApple() async {
        supabase.startAppleSignIn()
    }
    
    func signInWithGoogle() async {
        await supabase.signInWithGoogle()
    }
    
    @discardableResult
    func signOut() async -> Bool {
        await supabase.transitionToGhostSession()
    }

    @discardableResult
    func retryPendingSignOutPurchaseHandoff() async -> Bool {
        await supabase.retryPendingSignOutPurchaseHandoff()
    }
    
    /// Establishes a secure TCP/IP connection to the Supabase Edge natively pulling dynamic cloud-bound preferences 
    /// exclusively independently of the strictly offline local payload engines!
    func fetchGeoprivacy() {
        if !isGuestUser, let user = supabase.currentUser {
            Task {
                do {
                    // Ephemeral isolated Decodable Struct explicitly preventing globally polluting the namespace models.
                    struct CurrentSettings: Decodable { let default_geoprivacy: String }
                    let response: CurrentSettings = try await supabase.client.from("users")
                        .select("default_geoprivacy")
                        .eq("id", value: user.id)
                        .single()
                        .execute()
                        .value
                    self.defaultGeoprivacy = response.default_geoprivacy
                } catch {
                    MerianLog.network.error("Failed to fetch geoprivacy preference: \(error, privacy: .private)")
                }
            }
        }
    }

    func fetchPublicIdentity() async {
        guard let user = supabase.currentUser else {
            publicUsername = nil
            publicAuthorName = nil
            publicIdentitySource = nil
            publicAvatarUrl = nil
            isLoadingPublicIdentity = false
            return
        }

        isLoadingPublicIdentity = true
        defer { isLoadingPublicIdentity = false }

        do {
            let response: PublicProfileIdentity = try await supabase.client.from("users")
                .select("public_username,public_author_name,public_identity_source,public_avatar_url")
                .eq("id", value: user.id)
                .single()
                .execute()
                .value
            guard !Task.isCancelled, supabase.currentUser?.id == user.id else { return }
            publicUsername = response.publicUsername
            publicAuthorName = response.publicAuthorName
            publicIdentitySource = response.publicIdentitySource
            publicAvatarUrl = response.publicAvatarUrl
        } catch {
            guard !Task.isCancelled else { return }
            MerianLog.network.error("Failed to fetch public identity: \(error, privacy: .private)")
        }
    }

    func updatePublicAvatar(_ avatar: PreparedProfileAvatar) async -> Bool {
        guard let userId = currentUserId else {
            avatarUpdateErrorMessage = "Open a guest session before changing your profile picture."
            return false
        }

        guard avatar.data.count <= MerianConfig.stagedImagePayloadMaxBytes else {
            avatarUpdateErrorMessage = "Choose a smaller profile picture."
            return false
        }

        avatarUpdateErrorMessage = nil
        isUpdatingAvatar = true
        defer { isUpdatingAvatar = false }

        do {
            let fileName = MediaStagingContract.sanitizedFileName(
                "avatar_\(UUID().uuidString.lowercased()).\(avatar.fileExtension)"
            )
            let uploadFiles = [
                StagingUploadFile(
                    fileName: fileName,
                    mediaKind: .image,
                    contentType: avatar.contentType,
                    sizeBytes: avatar.data.count
                )
            ]
            let urls = try await MerianNetworkClient.shared.generateUploadURLs(uploadFiles: uploadFiles)
            guard let presignedURL = urls.first else {
                avatarUpdateErrorMessage = "Naturebook could not prepare that upload."
                return false
            }

            try await MerianNetworkClient.shared.uploadToR2(
                uploadURL: presignedURL,
                data: avatar.data,
                contentType: avatar.contentType
            )

            let response = try await MerianNetworkClient.shared.updatePublicAvatar(
                r2ObjectKey: presignedURL.objectKey,
                mimeType: avatar.contentType
            )
            guard currentUserId == userId else { return false }
            publicAvatarUrl = response.avatarUrl
            AppDIContainer.shared.appEventPublisher.send(
                .publicAuthorIdentityChanged(previousUserId: nil, currentUserId: userId)
            )
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            avatarUpdateErrorMessage = error.localizedDescription
            MerianLog.network.error("Failed to update public avatar: \(error, privacy: .private)")
            return false
        }
    }

    func updatePublicUsername(_ username: String) async -> Bool {
        guard let userId = currentUserId else {
            usernameUpdateErrorMessage = "Sign in or open a guest session first."
            return false
        }

        usernameUpdateErrorMessage = nil

        do {
            let response = try await MerianNetworkClient.shared.updatePublicUsername(username)
            guard currentUserId == userId else { return false }
            publicUsername = response.username
            if isGuestUser && publicIdentitySource != "display_name" {
                publicAuthorName = response.username
                publicIdentitySource = "alias"
            }
            AppDIContainer.shared.appEventPublisher.send(
                .publicAuthorIdentityChanged(previousUserId: nil, currentUserId: userId)
            )
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            usernameUpdateErrorMessage = publicUsernameErrorMessage(for: error)
            MerianLog.network.error("Failed to update public username: \(error, privacy: .private)")
            return false
        }
    }

    func updatePublicDisplayName(_ displayName: String) async -> Bool {
        guard let userId = currentUserId else {
            displayNameUpdateErrorMessage = "Open a guest session before changing your name."
            return false
        }

        displayNameUpdateErrorMessage = nil

        do {
            let response = try await MerianNetworkClient.shared.updatePublicDisplayName(displayName)
            guard currentUserId == userId else { return false }
            publicAuthorName = response.displayName
            publicIdentitySource = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "alias"
                : "display_name"
            AppDIContainer.shared.appEventPublisher.send(
                .publicAuthorIdentityChanged(previousUserId: nil, currentUserId: userId)
            )
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            displayNameUpdateErrorMessage = publicDisplayNameErrorMessage(for: error)
            MerianLog.network.error("Failed to update public display name: \(error, privacy: .private)")
            return false
        }
    }

    func checkPublicUsernameAvailability(_ username: String) async throws -> PublicUsernameAvailabilityResponse {
        try await MerianNetworkClient.shared.checkPublicUsernameAvailability(username)
    }

    private func publicUsernameErrorMessage(for error: Error) -> String {
        if case let MerianError.httpError(_, message) = error,
           let data = message.data(using: .utf8),
           let response = try? JSONDecoder().decode(PublicUsernameErrorResponse.self, from: data) {
            return response.error
        }
        return error.localizedDescription
    }

    private func publicDisplayNameErrorMessage(for error: Error) -> String {
        if case let MerianError.httpError(_, message) = error,
           let data = message.data(using: .utf8),
           let response = try? JSONDecoder().decode(PublicUsernameErrorResponse.self, from: data) {
            return response.error
        }
        return error.localizedDescription
    }

    func fetchSocialStats() async {
        guard !isGuestUser, let userId = currentUserId else {
            socialStats = nil
            isLoadingSocialStats = false
            return
        }

        socialStats = nil
        isLoadingSocialStats = true
        defer { isLoadingSocialStats = false }

        do {
            let profile = try await MerianNetworkClient.shared.getExploreAuthorProfile(
                authorUserId: userId,
                previewLimit: 0
            )
            guard !Task.isCancelled, currentUserId == userId else { return }
            let ownerSummary = profile.ownerPublicationSummary
            socialStats = ProfileSocialStats(
                followerCount: profile.followerCount,
                followingCount: profile.followingCount,
                visiblePublishedPostCount: ownerSummary?.visiblePostCount ?? profile.publishedPostCount,
                publicationIntentCount: ownerSummary?.publicationIntentCount ?? profile.publishedPostCount,
                recoveryNeededPostCount: ownerSummary?.recoveryNeededPostCount ?? 0,
                degradedPostCount: ownerSummary?.degradedPostCount ?? 0,
                quarantinedPostCount: ownerSummary?.quarantinedPostCount ?? 0
            )
        } catch {
            guard !Task.isCancelled else { return }
            MerianLog.network.error("Failed to fetch profile social stats: \(error, privacy: .private)")
        }
    }
}
