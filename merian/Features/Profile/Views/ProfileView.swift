import SwiftUI

enum ProfileTab {
    case profile
    case settings
}

struct ProfileView: View {
    // MARK: - Environment & State
    @Environment(\.dismiss) private var dismiss

    var supabase = SupabaseManager.shared
    @State private var viewModel = ProfileViewModel()
    @State private var showPaywall = false
    @State private var activeTab: ProfileTab = .profile

    /// Maps `ProfileTab` into the optional binding required by `.scrollPosition(id:)`.
    private var tabSelectionBinding: Binding<ProfileTab?> {
        Binding(
            get: { activeTab },
            set: { if let val = $0 { activeTab = val } }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ProfileTabView(supabase: supabase, showPaywall: $showPaywall)
                        .id(ProfileTab.profile)

                    SettingsTabView(supabase: supabase, viewModel: viewModel)
                        .id(ProfileTab.settings)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: tabSelectionBinding)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { profileToolbar }
            .onAppear {
                viewModel.fetchGeoprivacy()
            }
        }
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var profileToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
            }
        }

        ToolbarItem(placement: .principal) {
            Picker("View", selection: $activeTab) {
                Text("Profile").tag(ProfileTab.profile)
                Text("Settings").tag(ProfileTab.settings)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
    }
}
