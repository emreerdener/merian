import SwiftUI

@MainActor
final class UserProfileViewModel: ObservableObject {
    @Published var defaultGeoprivacy = "open"
    
    func fetchGeoprivacy(supabase: SupabaseManager) {
        if !supabase.isGuestUser, let user = supabase.currentUser {
            Task {
                do {
                    struct CurrentSettings: Decodable { let default_geoprivacy: String }
                    let response: CurrentSettings = try await supabase.client.from("users")
                        .select("default_geoprivacy")
                        .eq("id", value: user.id)
                        .single()
                        .execute()
                        .value
                    self.defaultGeoprivacy = response.default_geoprivacy
                } catch {
                    print("Error fetching geoprivacy: \(error)")
                }
            }
        }
    }
}
