import SwiftUI

/// Abstracted Danger Zone strictly firewalled into its own declarative layer natively.
/// Manages physical hard-deletes of SQLite rows, Auth rows, and physical disk bytes.
struct DangerZone: View {
    let supabase: SupabaseManager
    @Binding var isDeleting: Bool
    @Binding var showDeleteConfirmation: Bool
    
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
                Text("Clear Local Cache")
                    .foregroundColor(.red)
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
                        Text("Delete Account & Data")
                    }
                }
                .foregroundColor(.red)
            }
            .disabled(isDeleting)
        }
    }
}
