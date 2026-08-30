import SwiftUI

struct DangerZone: View {
    let supabase: SupabaseManager
    @Binding var showDeleteConfirmation: Bool

    @State private var viewModel: SettingsSignOutViewModel

    init(
        supabase: SupabaseManager,
        showDeleteConfirmation: Binding<Bool>
    ) {
        self.supabase = supabase
        _showDeleteConfirmation = showDeleteConfirmation
        _viewModel = State(
            initialValue: SettingsSignOutViewModel(
                dependencies: .live(supabase: supabase)
            )
        )
    }

    private var purchaseContinuityPending: Bool {
        viewModel.isPurchaseContinuityPending
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Section {
            if !supabase.isGuestUser {
                Button {
                    viewModel.showConfirmation = true
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(supabase.isAuthTransitionInProgress)
                .confirmationDialog(
                    "Are you sure you want to sign out?",
                    isPresented: $viewModel.showConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Sign out") {
                        Task { await performSignOut() }
                    }
                    Button("Cancel", role: .cancel) { }
                }
                .alert(
                    "Sign out incomplete",
                    isPresented: $viewModel.showError
                ) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(viewModel.errorMessage)
                }
            }

            Button {
                showDeleteConfirmation = true
            } label: {
                Label("Delete account & data", systemImage: "trash.fill")
            }
            .disabled(
                purchaseContinuityPending ||
                    supabase.isAuthTransitionInProgress
            )
            .foregroundColor(.red)
            .accessibilityHint(
                purchaseContinuityPending
                    ? "Finish signing out before deleting this account."
                    : "Permanently deletes this account and its account-owned data."
            )

            if purchaseContinuityPending {
                Text("Finish signing out before deleting this account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func performSignOut() async {
        await viewModel.signOut {
            supabase.isGuestUser
        }
    }
}
