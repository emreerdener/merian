import SwiftUI

struct DangerZone: View {
    let supabase: SupabaseManager
    @Binding var isDeleting: Bool
    @Binding var showDeleteConfirmation: Bool

    @State private var showSignOutConfirmation = false

    var body: some View {
        Section {
            Button("Clear local cache") {
                clearLocalCache()
            }
            .foregroundColor(.red)

            if !supabase.isGuestUser {
                Button("Sign out") {
                    showSignOutConfirmation = true
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
            }

            Button {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    if isDeleting {
                        ProgressView().tint(.red)
                    } else {
                        Text("Delete account & data")
                    }
                }
                .foregroundColor(.red)
            }
            .disabled(isDeleting)
        }
    }

    // MARK: - Actions

    private func clearLocalCache() {
        Task.detached(priority: .utility) {
            ImageCache.shared.clearCache()
            let cachesDir = URL.cachesDirectory
            if let enumerator = FileManager.default.enumerator(at: cachesDir, includingPropertiesForKeys: nil) {
                while let fileURL = enumerator.nextObject() as? URL {
                    // Preserve pending offline upload binaries backed by SwiftData records.
                    if fileURL.pathExtension == "jpg" && !fileURL.lastPathComponent.contains("_temp_upload") {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                }
            }
            await MainActor.run {
                HapticManager.shared.triggerSuccessPulse()
            }
        }
    }

    private func performSignOut() async {
        await supabase.signOut()
        await supabase.initializeGhostSession()
    }
}
