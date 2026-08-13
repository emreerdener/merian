import SwiftUI

enum ProfileTab {
    case profile
    case settings
}

struct ProfileView: View {
    // MARK: - Environment & State
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileViewModel.self) private var viewModel

    var supabase = SupabaseManager.shared
    @State private var showPaywall = false
    @State private var activeTab: ProfileTab = .profile
    @State private var isShowingAvatarPicker = false
    @State private var isShowingDisplayNameEditor = false
    @State private var isShowingUsernameEditor = false
    @State private var isShowingSignOutError = false
    @State private var signOutErrorMessage = SignOutPresentationPolicy
        .incompleteMessage(isAnonymousSession: false)

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
                    ProfileTabView(
                        showPaywall: $showPaywall,
                        isShowingAvatarPicker: $isShowingAvatarPicker,
                        isShowingDisplayNameEditor: $isShowingDisplayNameEditor,
                        isShowingUsernameEditor: $isShowingUsernameEditor
                    )
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
            .alert("Sign out incomplete", isPresented: $isShowingSignOutError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(signOutErrorMessage)
            }
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
            .padding(.bottom, 1)
            .background(Capsule().fill(.regularMaterial))
            .clipShape(Capsule())
            .frame(width: 200)
        }

        if activeTab == .profile {
            ToolbarItem(placement: .topBarTrailing) {
                profileOptionsMenu
            }
        }
    }

    private var profileOptionsMenu: some View {
        Menu {
            Button {
                isShowingAvatarPicker = true
            } label: {
                Label("Replace profile pic", systemImage: "person.crop.circle")
            }
            .disabled(viewModel.isUpdatingAvatar)

            Button {
                isShowingDisplayNameEditor = true
            } label: {
                Label("Edit name", systemImage: "person.text.rectangle")
            }

            Button {
                isShowingUsernameEditor = true
            } label: {
                Label("Edit username", systemImage: "at")
            }

            if !viewModel.isGuestUser {
                Button(role: .destructive) {
                    Task {
                        if !(await viewModel.signOut()) {
                            signOutErrorMessage = SignOutPresentationPolicy
                                .incompleteMessage(
                                    isAnonymousSession: viewModel.isGuestUser
                                )
                            isShowingSignOutError = true
                        }
                    }
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(supabase.isAuthTransitionInProgress)
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .tint(.primary)
        .disabled(supabase.isAuthTransitionInProgress)
        .accessibilityLabel("Profile options")
        .accessibilityIdentifier("ProfileToolbarOptions")
    }
}
