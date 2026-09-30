import SwiftUI

struct SettingsTabView: View {
    @Environment(RevenueCatManager.self) private var revenueCatManager
    var supabase: SupabaseManager
    @Bindable var viewModel: ProfileViewModel
    let geoprivacyDependencies: GeoprivacySettingsDependencies
    let preferenceActions: SettingsPreferenceActions

    // MARK: - State
    @State private var isExporting = false
    @State private var exportUrl: URL?
    @State private var safariUrl: URL?
    @State private var managePlanActive = false
    @State private var notificationSettingsActive = false
    @State private var changelogActive = false
    @State private var cameraSettingsActive = false
    @State private var audioRecordingSettingsActive = false
    @State private var captureModeOrderSettingsActive = false
    @State private var activeSheet: SettingsSheet?
    @State private var toastMessage: ToastPayload?

    var body: some View {
        ZStack {
            List {
                Preferences(
                    defaultGeoprivacy: $viewModel.defaultGeoprivacy,
                    managePlanActive: $managePlanActive,
                    notificationSettingsActive: $notificationSettingsActive,
                    cameraSettingsActive: $cameraSettingsActive,
                    audioRecordingSettingsActive: $audioRecordingSettingsActive,
                    captureModeOrderSettingsActive: $captureModeOrderSettingsActive,
                    showPaywall: isPresenting(.paywall),
                    showTestExploreOnboarding: isPresenting(.exploreOnboarding),
                    geoprivacyDependencies: geoprivacyDependencies,
                    preferenceActions: preferenceActions
                )

                if FeatureFlags.isEnabled(.dwcaExports) {
                    ExportScans(
                        supabase: supabase,
                        isExporting: $isExporting,
                        exportUrl: $exportUrl,
                        onExportRequested: {
                            toastMessage = .success(
                                "Export requested. Check your email shortly."
                            )
                        }
                    )
                }

                Community(
                    changelogActive: $changelogActive,
                    showWhatsNew: isPresenting(.whatsNew),
                    safariUrl: $safariUrl,
                    showSafari: isPresenting(.safari),
                    showFeedbackSurvey: isPresenting(.feedback)
                )

                DangerZone(
                    supabase: supabase,
                    showDeleteConfirmation: isPresenting(.deleteAccount)
                )
            }
            .transparentTopToolbar()
            .navigationDestination(isPresented: $notificationSettingsActive) {
                NotificationSettingsView()
            }
            .navigationDestination(isPresented: $changelogActive) {
                ChangelogView()
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
                    .environment(revenueCatManager)
            }
            .listStyle(InsetGroupedListStyle())
            .contentMargins(.top, 16, for: .scrollContent)
            .containerRelativeFrame(.horizontal)
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .safari:
                    if let url = safariUrl {
                        SafariView(url: url)
                    }
                case .deleteAccount:
                    DeleteAccountSheet(supabase: supabase)
                case .paywall:
                    PaywallView()
                        .environment(revenueCatManager)
                case .feedback:
                    FeedbackSurveyView()
                case .whatsNew:
                    WhatsNewSheet()
                case .exploreOnboarding:
                    ExploreOnboardingPrompt(
                        onShare: { activeSheet = nil },
                        onDismiss: { activeSheet = nil }
                    )
                }
            }
        }
        .merianSystemFeedback(
            toast: $toastMessage,
            milestoneAlignment: .top
        )
    }

    private func isPresenting(_ sheet: SettingsSheet) -> Binding<Bool> {
        Binding(
            get: { activeSheet == sheet },
            set: { isPresented in
                if isPresented {
                    guard activeSheet == nil else { return }
                    activeSheet = sheet
                } else if activeSheet == sheet {
                    activeSheet = nil
                }
            }
        )
    }
}

private enum SettingsSheet: String, Identifiable {
    case safari, deleteAccount, paywall, feedback, whatsNew, exploreOnboarding

    var id: String { rawValue }
}
