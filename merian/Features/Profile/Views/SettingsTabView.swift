import SwiftData
import SwiftUI

struct SettingsTabView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var supabase: SupabaseManager
    @Bindable var viewModel: ProfileViewModel

    // MARK: - Feature Toggles
    @AppStorage("isExpeditionModeActive") private var isExpeditionModeActive = false
    @AppStorage("isHapticsEnabled") private var isHapticsEnabled = true

    // MARK: - State
    @State private var isExporting = false
    @State private var exportUrl: URL?
    @State private var showSafari = false
    @State private var safariUrl: URL?
    @State private var showDeleteConfirmation = false
    @State private var managePlanActive = false
    @State private var notificationSettingsActive = false
    @State private var cameraSettingsActive = false

    var body: some View {
        List {
            Preferences(
                isHapticsEnabled: $isHapticsEnabled,
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
        .sheet(isPresented: $showDeleteConfirmation) {
            DeleteAccountSheet(supabase: supabase)
        }
    }

}
