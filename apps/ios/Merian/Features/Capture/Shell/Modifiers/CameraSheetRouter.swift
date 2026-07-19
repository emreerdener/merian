import SwiftUI

struct CameraSheetRouter: ViewModifier {
    @Bindable var viewModel: CaptureWorkspaceViewModel
    @State private var showNotificationPrompt = false
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(AppSettings.self) private var appSettings
    
    func body(content: Content) -> some View {
        content
            .sheet(item: $viewModel.activeSheet, onDismiss: {
                viewModel.handleRootSheetDismissed()
            }) { sheet in
                Group {
                    switch sheet {
                    case .insight:
                        InsightSheetView(isPresented: Binding(
                            get: { viewModel.activeSheet == .insight },
                            set: { 
                                if !$0 && viewModel.activeSheet == .insight { 
                                    viewModel.activeSheet = nil 
                                    if !appSettings.hasPromptedForNotificationsPostIdent {
                                        appSettings.hasPromptedForNotificationsPostIdent = true
                                        Task { @MainActor in
                                            try? await Task.sleep(for: .milliseconds(500))
                                            self.showNotificationPrompt = true
                                        }
                                    }
                                } 
                            }
                        ), inferenceEngine: inferenceEngine)
                        .onAppear {
                            appSettings.hasUnseenScan = false
                            AppIconBadgeCoordinator.updateAppIconBadge()
                        }
                    case .paywall:
                        PaywallView()
                    case .profile:
                        ProfileView()
                    case .explore:
                        ExploreView(
                            initialPostId: viewModel.pendingExplorePostId,
                            initialCommunityRequestId: viewModel.pendingCommunityIdentificationRequestId,
                            initialTargetCommentId: viewModel.pendingExploreTargetCommentId,
                            initialTargetReplyParentCommentId: viewModel.pendingExploreTargetReplyParentCommentId,
                            initialCaptureGoalDestination: viewModel.pendingCaptureGoalDestination,
                            initialTab: viewModel.pendingExploreShowsFieldTrips ? .fieldTrips : .feed
                        )
                            .id(viewModel.explorePresentationIdentity)
                            .onAppear {
                                appSettings.hasSeenExploreNewChip = true
                            }
                            .onDisappear {
                                viewModel.pendingExplorePostId = nil
                                viewModel.pendingCommunityIdentificationRequestId = nil
                                viewModel.pendingExploreTargetCommentId = nil
                                viewModel.pendingExploreTargetReplyParentCommentId = nil
                                viewModel.pendingCaptureGoalDestination = nil
                                viewModel.pendingExploreShowsFieldTrips = false
                            }
                    case .scans:
                        ScansSheetView()
                        .onAppear {
                            appSettings.hasUnseenScan = false
                            AppIconBadgeCoordinator.updateAppIconBadge()
                        }
                    }
                }
                .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $showNotificationPrompt) {
                PostIdentificationNotificationSheetView { granted in
                    appSettings.isPushNotificationsEnabled = granted
                    showNotificationPrompt = false
                }
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.hidden)
            }
    }
}

extension View {
    func cameraSheetRouter(viewModel: CaptureWorkspaceViewModel) -> some View {
        self.modifier(CameraSheetRouter(viewModel: viewModel))
    }
}
