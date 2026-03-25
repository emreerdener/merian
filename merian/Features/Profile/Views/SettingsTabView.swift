import SwiftUI
import SwiftData

struct SettingsTabView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var supabase: SupabaseManager
    @Bindable var viewModel: ProfileViewModel

    // MARK: - Feature Toggles
    @AppStorage("isExpeditionModeActive") private var isExpeditionModeActive = false
    @AppStorage("isHapticsEnabled") private var isHapticsEnabled = true
    @AppStorage("saveToCameraRoll") private var saveToCameraRoll = true

    // MARK: - State
    @State private var isExporting = false
    @State private var exportUrl: URL?
    @State private var showSafari = false
    @State private var safariUrl: URL?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var managePlanActive = false
    @State private var notificationSettingsActive = false
    @State private var cameraSettingsActive = false

    var body: some View {
        List {
            Preferences(
                isHapticsEnabled: $isHapticsEnabled,
                saveToCameraRoll: $saveToCameraRoll,
                defaultGeoprivacy: $viewModel.defaultGeoprivacy,
                managePlanActive: $managePlanActive,
                notificationSettingsActive: $notificationSettingsActive,
                cameraSettingsActive: $cameraSettingsActive
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
        .navigationDestination(isPresented: $notificationSettingsActive) {
            NotificationSettingsView()
        }
        .navigationDestination(isPresented: $cameraSettingsActive) {
            CameraSettingsView()
        }
        .navigationDestination(isPresented: $managePlanActive) {
            ManagePlanView()
                .environment(RevenueCatManager.shared)
        }
        .listStyle(InsetGroupedListStyle())
        .containerRelativeFrame(.horizontal)
        .onAppear {
            isExpeditionModeActive = HardwareOrchestrator.shared.isExpeditionModeActive
        }
        .sheet(isPresented: $showSafari) {
            if let url = safariUrl {
                SafariView(url: url)
            }
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
