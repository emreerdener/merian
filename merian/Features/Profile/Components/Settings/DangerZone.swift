import SwiftUI

/// Abstracted Danger Zone strictly firewalled into its own declarative layer natively.
/// Manages physical hard-deletes of SQLite rows, Auth rows, and physical disk bytes.
struct DangerZone: View {
    let supabase: SupabaseManager
    @Binding var isDeleting: Bool
    @Binding var showDeleteConfirmation: Bool
    
    @State private var showSignOutConfirmation = false
    
    var body: some View {
        Section {
            Button(action: {
                // Instantly detaches the heavyweight massive recursive `FileManager` block physically
                // off the active UI geometry thread preventing scroll frame-drops natively!
                Task.detached(priority: .utility) {
                    ImageCache.shared.clearCache()
                    let cachesDir = URL.cachesDirectory
                    if let enumerator = FileManager.default.enumerator(at: cachesDir, includingPropertiesForKeys: nil) {
                        while let fileURL = enumerator.nextObject() as? URL {
                            // Specifically preserves active `_temp_upload` binaries inherently backing 
                            // pending offline SwiftData structs syncing to the physical PostgreSQL edge!
                            if fileURL.pathExtension == "jpg" && !fileURL.lastPathComponent.contains("_temp_upload") {
                                try? FileManager.default.removeItem(at: fileURL)
                            }
                        }
                    }
                    await MainActor.run {
                        HapticManager.shared.triggerSuccessPulse()
                    }
                }
            }) {
                Text("Clear local cache")
                    .foregroundColor(.red)
            }
            
            Button(action: {
                showSignOutConfirmation = true
            }) {
                Text("Sign out")
                    .foregroundColor(.red)
            }
            .confirmationDialog(
                "Are you sure you want to sign out?",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    Task {
                        // Forces a clean physical JWT removal across the device securely
                        // instantly rehydrating back into a zero-bound Ghost mode state.
                        await supabase.signOut()
                        await supabase.initializeGhostSession()
                    }
                }
                Button("Cancel", role: .cancel) { }
            }

            Button(action: {
                // Bubbles the destructive confirmation strictly up to `SettingsTabView` safely orchestrating changes!
                showDeleteConfirmation = true
            }) {
                HStack {
                    if isDeleting {
                        ProgressView()
                            .tint(.red)
                    } else {
                        Text("Delete account & data")
                    }
                }
                .foregroundColor(.red)
            }
            .disabled(isDeleting)
        }
    }
}
