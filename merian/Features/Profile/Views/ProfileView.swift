import SwiftUI

enum ProfileTab {
    case profile
    case settings
}

/// The master routing orchestrator for the Profile tab.
/// This View strictly handles geometric layout boundaries (.paging, toolbars)
/// and delegates all actual domain logic entirely into `ProfileTabView` and `SettingsTabView`.
struct ProfileView: View {
    // MARK: - Environment & State
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - View Models & Managers
    var supabase = SupabaseManager.shared
    @State private var viewModel = ProfileViewModel()
    
    // MARK: - UI State
    @State private var showPaywall = false
    @State private var activeTab: ProfileTab = .profile
    
    // MARK: - Derived Bindings
    /// iOS 17's `.scrollPosition(id:)` expects an Optional Hashable binding.
    /// This computed property seamlessly maps our non-optional `activeTab` State
    /// cleanly into the modifier without compiler type mismatches.
    private var tabSelectionBinding: Binding<ProfileTab?> {
        Binding(
            get: { activeTab },
            set: { if let newValue = $0 { activeTab = newValue } }
        )
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            // A horizontal ScrollView explicitly bounded to `.paging` behavior.
            // This natively mimics standard Tab swipe dynamics without locking 
            // the layout away behind a standard rigid UIKit UITabBarController.
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
            // Implicitly synchronizes the user's swiping gesture back into the Segmented Picker
            .scrollPosition(id: tabSelectionBinding)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { profileToolbar }
            .onAppear {
                viewModel.fetchGeoprivacy()
            }
        }
    }
    
    // MARK: - Toolbar Construction
    @ToolbarContentBuilder
    private var profileToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
            }
        }
        
        // Native Apple Segmented Control perfectly proxying the $activeTab scroll tracking
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
