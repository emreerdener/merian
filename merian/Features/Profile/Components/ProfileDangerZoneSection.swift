import SwiftUI

struct ProfileDangerZoneSection: View {
    let supabase: SupabaseManager
    @Binding var isDeleting: Bool
    @Binding var showDeleteConfirmation: Bool
    
    var body: some View {
        Section {
            Button(action: {
                Task.detached(priority: .utility) {
                    ImageCache.shared.clearCache()
                    let cachesDir = URL.cachesDirectory
                    if let enumerator = FileManager.default.enumerator(at: cachesDir, includingPropertiesForKeys: nil) {
                        while let fileURL = enumerator.nextObject() as? URL {
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
            
            UserProfileAuthSection(supabase: supabase)
                
            Button(action: {
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
