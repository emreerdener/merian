import SwiftUI

struct DangerZone: View {
    let supabase: SupabaseManager
    @Binding var showDeleteConfirmation: Bool
    var onCacheCleared: ((Bool) -> Void)?

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

            Button("Delete account & data") {
                showDeleteConfirmation = true
            }
            .foregroundColor(.red)
        }
    }

    // MARK: - Actions

    private func clearLocalCache() {
        Task.detached(priority: .utility) {
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
        await supabase.signOut()
        await supabase.initializeGhostSession()
    }
}
