import SwiftUI
import SwiftData

struct SettingsTabView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var supabase: SupabaseManager
    @Bindable var viewModel: ProfileViewModel

    // MARK: - Feature Toggles
    @AppStorage("isExpeditionModeActive") private var isExpeditionModeActive = false
    @AppStorage("isLiveInferencePaused") private var isLiveInferencePaused = UIDevice.current.isModernIPhone
    @AppStorage("isHapticsEnabled") private var isHapticsEnabled = true
    @AppStorage("saveToCameraRoll") private var saveToCameraRoll = true

    // MARK: - State
    @State private var isExporting = false
    @State private var exportUrl: URL?
    @State private var showSafari = false
    @State private var safariUrl: URL?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showPaywall = false

    var body: some View {
        List {
            Preferences(
                isLiveInferencePaused: $isLiveInferencePaused,
                isHapticsEnabled: $isHapticsEnabled,
                saveToCameraRoll: $saveToCameraRoll,
                defaultGeoprivacy: $viewModel.defaultGeoprivacy,
                showPaywall: $showPaywall
            )

            ExportScans(
                supabase: supabase,
                isExporting: $isExporting,
                exportUrl: $exportUrl
            )

            Community(
                safariUrl: $safariUrl,
                showSafari: $showSafari
            )

            DangerZone(
                supabase: supabase,
                isDeleting: $isDeleting,
                showDeleteConfirmation: $showDeleteConfirmation
            )
        }
        .listStyle(InsetGroupedListStyle())
        .containerRelativeFrame(.horizontal)
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
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Actions

    private func deleteAccount() async {
        isDeleting = true
        do {
            try await MerianNetworkClient.shared.safeDeleteAccount()
            await supabase.signOut()
            ScanRepository.shared.purgeAllData(modelContext: modelContext)
            dismiss()
        } catch {
            MerianLog.general.error("Account deletion failed: \(error.localizedDescription, privacy: .public)")
        }
        isDeleting = false
    }
}
