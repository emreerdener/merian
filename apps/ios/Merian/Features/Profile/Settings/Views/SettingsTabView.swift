import SwiftData
import SwiftUI

struct SettingsTabView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var supabase: SupabaseManager
    @Bindable var viewModel: ProfileViewModel

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
    @State private var toastMessage: String?
    @State private var achievementToastPresenter = AchievementToastPresenter.shared
    @State private var selectedAchievementToastAward: AwardPayload?

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
                    showTestExploreOnboarding: $showTestExploreOnboarding
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
                    changelogActive: $changelogActive,
                    safariUrl: $safariUrl,
                    showSafari: $showSafari,
                    showFeedbackSurvey: $showFeedbackSurvey
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
                    .environment(RevenueCatManager.shared)
            }
            .listStyle(InsetGroupedListStyle())
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
                    .environment(RevenueCatManager.shared)
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

            if let item = achievementToastPresenter.activeUnlock {
                AchievementToastBanner(
                    item: item,
                    onDismiss: {
                        achievementToastPresenter.dismissActiveUnlock(id: item.id)
                    },
                    onOpen: {
                        selectedAchievementToastAward = item.award
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(110)
            }
        }
        .sheet(item: $selectedAchievementToastAward) { award in
            AchievementDetailSheet(award: award, modelContainer: modelContext.container)
        }
    }

}
