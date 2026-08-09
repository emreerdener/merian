import SwiftUI

struct DangerZone: View {
    let supabase: SupabaseManager
    @Binding var showDeleteConfirmation: Bool
    var onCacheCleared: ((Bool) -> Void)?

    @State private var showGhostModeConfirmation = false

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
                    showGhostModeConfirmation = true
                } label: {
                    Label("Continue as Ghost", systemImage: "theatermasks")
                }
                .foregroundColor(.red)
                .confirmationDialog(
                    "Continue as Ghost on this device?",
                    isPresented: $showGhostModeConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Continue as Ghost") {
                        performContinueAsGhost()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Your Naturebook user, scans, Pro access, and purchases stay with the same private account. This does not delete data or revoke the linked sign-in provider.")
                }
            }

            Button {
                showDeleteConfirmation = true
            } label: {
                Label("Delete account & data", systemImage: "trash.fill")
            }
            .foregroundColor(.red)
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

    private func performContinueAsGhost() {
        _ = supabase.continueAsGhost()
    }
}
