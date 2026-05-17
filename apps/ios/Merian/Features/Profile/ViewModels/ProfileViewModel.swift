import Observation
import SwiftUI

struct ProfileSocialStats: Equatable {
    let followerCount: Int
    let followingCount: Int
    let publishedPostCount: Int
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
        if let avatarStr = supabase.currentUser?.userMetadata["avatar_url"]?.stringValue ?? supabase.currentUser?.userMetadata["picture"]?.stringValue,
           let url = URL(string: avatarStr) {
            return url
        }
        return nil
    }
    
    // MARK: - Auth Flow Actions
    func signInWithApple() async {
        supabase.startAppleSignIn()
    }
    
    func signInWithGoogle() async {
        await supabase.signInWithGoogle()
    }
    
    func signOut() async {
        await supabase.signOut()
        await supabase.initializeGhostSession()
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
            socialStats = ProfileSocialStats(
                followerCount: profile.followerCount,
                followingCount: profile.followingCount,
                publishedPostCount: profile.publishedPostCount
            )
        } catch {
            guard !Task.isCancelled else { return }
            MerianLog.network.error("Failed to fetch profile social stats: \(error, privacy: .private)")
        }
    }
}
