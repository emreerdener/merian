import SwiftUI
import SwiftData

/// A heavily decoupled feature list explicitly abstracted entirely out of `ProfileView`.
/// Isolating `SettingsTabView` physically prevents its 10+ massive `@AppStorage` toggles
/// from continuously triggering layout invalidations and stuttering the parent horizontal scroll geometry!
struct SettingsTabView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var supabase: SupabaseManager
    @Bindable var viewModel: ProfileViewModel
    
    // Feature Toggles (AppStorage)
    @AppStorage("isExpeditionModeActive") private var isExpeditionModeActive = false
    @AppStorage("isLiveInferencePaused") private var isLiveInferencePaused = UIDevice.current.isModernIPhone
    @AppStorage("isHapticsEnabled") private var isHapticsEnabled = true
    @AppStorage("saveToCameraRoll") private var saveToCameraRoll = true
    
    // Privacy States
    @State private var isExporting = false
    @State private var exportUrl: URL?
    @State private var showSafari = false
    @State private var safariUrl: URL?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showPaywall = false
    
    var body: some View {
        List {
            // Section 2: Field & Hardware Preferences
            Preferences(
                isLiveInferencePaused: $isLiveInferencePaused,
                isHapticsEnabled: $isHapticsEnabled,
                saveToCameraRoll: $saveToCameraRoll,
                defaultGeoprivacy: $viewModel.defaultGeoprivacy,
                showPaywall: $showPaywall
            )
            
            // Section 3: Privacy & Citizen Science
            ExportScans(
                supabase: supabase,
                isExporting: $isExporting,
                exportUrl: $exportUrl
            )
            
            // Section 5: Legal & Community
            Community(
                safariUrl: $safariUrl,
                showSafari: $showSafari
            )
            
            // Section 6: Danger Zone
            DangerZone(
                supabase: supabase,
                isDeleting: $isDeleting,
                showDeleteConfirmation: $showDeleteConfirmation
            )
        }
        .listStyle(InsetGroupedListStyle())
        // Explicitly binds this list to exactly 100% of the screen width securely, 
        // creating a perfect 1-to-1 swipeable "Page" geometry for the parent Pagination axis!
        .containerRelativeFrame(.horizontal)
        // Overrides UI toggles dynamically using immutable Hardware singletons so real-time capabilities 
        // (like thermal throttling) mathematically perfectly match the state toggles identically upon visibility.
        .onAppear {
            isExpeditionModeActive = HardwareOrchestrator.shared.isExpeditionModeActive
            isLiveInferencePaused = CameraManager.shared.isLiveInferencePaused
        }
        .sheet(isPresented: $showSafari) {
            if let url = safariUrl {
                SafariView(url: url)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(RevenueCatManager.shared)
        }
        .confirmationDialog(
            "Are you sure you want to permanently delete your account and all associated data?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task {
                    isDeleting = true
                    do {
                        // Natively triggers a cascade wipe universally dropping all local bytes and remote credentials!
                        // 1. Physically drops native Supabase rows.
                        // 2. Purges the local auth session completely.
                        // 3. Empties all SwiftData SQLite vectors entirely.
                        // 4. Dismantles the overarching Profile Sheet dynamically mapping the user straight to Camera root!
                        try await MerianNetworkClient.shared.safeDeleteAccount()
                        await supabase.signOut()
                        ScanRepository.shared.purgeAllData(modelContext: modelContext)
                        dismiss()
                    } catch {
                        print("🚨 Safe delete failed: \(error.localizedDescription)")
                    }
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
