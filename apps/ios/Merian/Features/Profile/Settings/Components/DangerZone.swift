import SwiftUI

struct DangerZone: View {
    let supabase: SupabaseManager
    @Binding var showDeleteConfirmation: Bool

    @State private var showSignOutConfirmation = false
    @State private var showSignOutError = false
    @State private var signOutErrorMessage = SignOutPresentationPolicy
        .incompleteMessage(isAnonymousSession: false)

    private var purchaseContinuityPending: Bool {
        RevenueCatManager.shared.isPurchaseIdentityHandoffPending
    }

    var body: some View {
        Section {
            if !supabase.isGuestUser {
                Button {
                    showSignOutConfirmation = true
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(supabase.isAuthTransitionInProgress)
                .confirmationDialog(
                    "Are you sure you want to sign out?",
                    isPresented: $showSignOutConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Sign out") {
                        Task { await performSignOut() }
                    }
                    Button("Cancel", role: .cancel) { }
                }
                .alert("Sign out incomplete", isPresented: $showSignOutError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(signOutErrorMessage)
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
        if !(await supabase.transitionToGhostSession()) {
            signOutErrorMessage = SignOutPresentationPolicy.incompleteMessage(
                isAnonymousSession: supabase.isGuestUser
            )
            showSignOutError = true
        }
    }
}
