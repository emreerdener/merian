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
    @State private var showSafari = false
    @State private var safariUrl: URL?
    @State private var showDeleteConfirmation = false
    @State private var managePlanActive = false
    @State private var notificationSettingsActive = false
    @State private var changelogActive = false
    @State private var cameraSettingsActive = false
    @State private var audioRecordingSettingsActive = false
    @State private var captureModeOrderSettingsActive = false
    @State private var showTestExploreOnboarding = false
    @State private var showPaywall = false
    @State private var showFeedbackSurvey = false
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
                    showPaywall: $showPaywall,
                    showTestExploreOnboarding: $showTestExploreOnboarding,
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
                    safariUrl: $safariUrl,
                    showSafari: $showSafari,
                    showFeedbackSurvey: $showFeedbackSurvey
                )

                DangerZone(
                    supabase: supabase,
                    showDeleteConfirmation: $showDeleteConfirmation
                )
            }
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
            .sheet(isPresented: $showSafari) {
                if let url = safariUrl {
                    SafariView(url: url)
                }
            }
            .sheet(isPresented: $showDeleteConfirmation) {
                DeleteAccountSheet(supabase: supabase)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environment(revenueCatManager)
            }
            .sheet(isPresented: $showFeedbackSurvey) {
                FeedbackSurveyView()
            }
            .sheet(isPresented: $showTestExploreOnboarding) {
                ExploreOnboardingPrompt(
                    onShare: { showTestExploreOnboarding = false },
                    onDismiss: { showTestExploreOnboarding = false }
                )
            }
        }
        .merianSystemFeedback(
            toast: $toastMessage,
            milestoneAlignment: .top
        )
    }
}
