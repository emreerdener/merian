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
    @State private var audioRecordingSettingsActive = false
    @State private var captureModeOrderSettingsActive = false
    @State private var toastMessage: String?

    var body: some View {
        ZStack {
            List {
                Preferences(
                    isHapticsEnabled: $isHapticsEnabled,
                    defaultGeoprivacy: $viewModel.defaultGeoprivacy,
                    managePlanActive: $managePlanActive,
                    notificationSettingsActive: $notificationSettingsActive,
                    cameraSettingsActive: $cameraSettingsActive,
                    audioRecordingSettingsActive: $audioRecordingSettingsActive,
                    captureModeOrderSettingsActive: $captureModeOrderSettingsActive
                )

                ExportScans(
                    supabase: supabase,
                    isExporting: $isExporting,
                    exportUrl: $exportUrl,
                    onExportRequested: {
                        withAnimation { toastMessage = "Export requested. Check your email shortly." }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                            withAnimation { toastMessage = nil }
                        }
                    }
                )

                Community(
                    safariUrl: $safariUrl,
                    showSafari: $showSafari
                )

                DangerZone(
                    supabase: supabase,
                    showDeleteConfirmation: $showDeleteConfirmation,
                    onCacheCleared: { success in
                        if success {
                            toastMessage = "Local cache cleared"
                        } else {
                            toastMessage = "Error clearing some files"
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                            withAnimation {
                                toastMessage = nil
                            }
                        }
                    }
                )
            }
            .navigationDestination(isPresented: $notificationSettingsActive) {
                NotificationSettingsView()
            }
            .navigationDestination(isPresented: $cameraSettingsActive) {
                CameraSettingsView()
            }
            .navigationDestination(isPresented: $audioRecordingSettingsActive) {
                AudioRecordingSettingsView()
            }
            .navigationDestination(isPresented: $captureModeOrderSettingsActive) {
                CaptureModeSettingsView()
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

            if let message = toastMessage {
                ToastBanner(onDismiss: {
                    withAnimation {
                        toastMessage = nil
                    }
                }) {
                    Text(message)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
    }

}
