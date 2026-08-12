import SwiftUI

struct DangerZone: View {
    let supabase: SupabaseManager
    @Binding var showDeleteConfirmation: Bool
    var onCacheCleared: ((Bool) -> Void)?

    @State private var showSignOutConfirmation = false
    @State private var showSignOutError = false
    @State private var signOutErrorMessage = SignOutPresentationPolicy
        .incompleteMessage(isAnonymousSession: false)

    private var purchaseContinuityPending: Bool {
        RevenueCatManager.shared.isPurchaseIdentityHandoffPending
    }

    var body: some View {
        Section {
            Button {
                clearLocalCache()
            } label: {
                Label("Clear local cache", systemImage: "arrow.counterclockwise.circle")
            }
            .foregroundColor(.red)

            if !supabase.isGuestUser {
                Button {
                    showSignOutConfirmation = true
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .foregroundColor(.red)
                .confirmationDialog(
                    "Are you sure you want to sign out?",
                    isPresented: $showSignOutConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Sign out", role: .destructive) {
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
            .disabled(purchaseContinuityPending)
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

    private func clearLocalCache() {
        DetachedWork.fireAndForget(
            priority: .utility,
            category: .fileSystemCleanup
        ) {
            ImageCache.shared.clearCache()
            let cachesDir = URL.cachesDirectory
            var hasError = false
            if let enumerator = FileManager.default.enumerator(at: cachesDir, includingPropertiesForKeys: nil) {
                while let fileURL = enumerator.nextObject() as? URL {
                    // Preserve pending offline upload binaries backed by SwiftData records.
                    if fileURL.pathExtension == "jpg" && !fileURL.lastPathComponent.contains("_temp_upload") {
                        do {
                            try FileManager.default.removeItem(at: fileURL)
                        } catch {
                            hasError = true
                        }
                    }
                }
            }
            let finalHasError = hasError
            await MainActor.run {
                if !finalHasError {
                    HapticManager.shared.triggerSuccessPulse()
                } else {
                    HapticManager.shared.triggerErrorThump()
                }
                withAnimation {
                    onCacheCleared?(!finalHasError)
                }
            }
        }
    }

    private func performSignOut() async {
        if !(await supabase.transitionToGhostSession()) {
            signOutErrorMessage = SignOutPresentationPolicy.incompleteMessage(
                isAnonymousSession: supabase.isGuestUser
            )
            showSignOutError = true
        }
    }
}
