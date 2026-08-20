import SwiftUI

struct CameraSheetRouter: ViewModifier {
    @Bindable var viewModel: CaptureWorkspaceViewModel
    var onDismiss: () -> Void = {}
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.modelContext) private var modelContext
    @State private var isPresentingInsight = false
    
    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: { viewModel.activePresentation },
                set: { newValue in
                    if let newValue {
                        switch newValue.destination {
                        case .insight:
                            isPresentingInsight = true
                        default:
                            isPresentingInsight = false
                        }
                        viewModel.activePresentation = newValue
                    } else {
                        if isPresentingInsight {
                            inferenceEngine.dismissAnalyzingPresentation()
                        }
                        isPresentingInsight = false
                        viewModel.dismissActivePresentation()
                    }
                }
            ), onDismiss: {
                if isPresentingInsight {
                    inferenceEngine.dismissAnalyzingPresentation()
                    isPresentingInsight = false
                }
                viewModel.handleRootSheetDismissed()
                onDismiss()
            }) { presentation in
                Group {
                    switch presentation.destination {
                    case .insight:
                        InsightSheetView(isPresented: Binding(
                            get: { viewModel.activeSheet == .insight },
                            set: { 
                                if !$0 && viewModel.activeSheet == .insight { 
                                    inferenceEngine.dismissAnalyzingPresentation()
                                    isPresentingInsight = false
                                    if !appSettings.hasPromptedForNotificationsPostIdent {
                                        appSettings.hasPromptedForNotificationsPostIdent = true
                                        viewModel.queueNotificationPromptAfterInsightDismissal()
                                    }
                                    viewModel.dismissActivePresentation()
                                } 
                            }
                        ), inferenceEngine: inferenceEngine)
                        .onAppear {
                            isPresentingInsight = true
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
                            initialSpeciesDictionaryRoute: viewModel.pendingSpeciesDictionaryRoute,
                            initialCommunityRequestId: viewModel.pendingCommunityIdentificationRequestId,
                            initialTargetCommentId: viewModel.pendingExploreTargetCommentId,
                            initialTargetReplyParentCommentId: viewModel.pendingExploreTargetReplyParentCommentId,
                            initialCaptureGoalDestination: viewModel.pendingCaptureGoalDestination,
                            initialTab: viewModel.pendingExploreShowsFieldTrips ? .fieldTrips : .feed
                        )
                            .id(viewModel.explorePresentationIdentity)
                            .onDisappear {
                                viewModel.pendingExplorePostId = nil
                                viewModel.pendingSpeciesDictionaryRoute = nil
                                viewModel.pendingCommunityIdentificationRequestId = nil
                                viewModel.pendingExploreTargetCommentId = nil
                                viewModel.pendingExploreTargetReplyParentCommentId = nil
                                viewModel.pendingCaptureGoalDestination = nil
                                viewModel.pendingExploreShowsFieldTrips = false
                            }
                    case .scans:
                        ScansSheetView(
                            recoveryContext: viewModel.pendingScansRecoveryContext,
                            initiallyShowsNonBiologicalScans:
                                viewModel.pendingScansShowsNonBiologicalCollection
                        )
                        .onAppear {
                            appSettings.hasUnseenScan = false
                            AppIconBadgeCoordinator.updateAppIconBadge()
                        }
                        .onDisappear {
                            viewModel.pendingScansRecoveryContext = nil
                            viewModel.pendingScansShowsNonBiologicalCollection = false
                        }
                    case .achievement:
                        if let award = viewModel.pendingAchievementAward {
                            AchievementDetailSheet(
                                award: award,
                                modelContainer: modelContext.container
                            )
                            .onDisappear {
                                viewModel.pendingAchievementAward = nil
                            }
                        }
                    case .notificationPrompt:
                        PostIdentificationNotificationSheetView { granted in
                            appSettings.isPushNotificationsEnabled = granted
                            viewModel.dismissActivePresentation()
                        }
                        .presentationDetents([.height(320)])
                        .presentationDragIndicator(.hidden)
                    }
                }
                .id(presentation.id)
                .presentationDragIndicator(.hidden)
            }
    }
}

extension View {
    func cameraSheetRouter(
        viewModel: CaptureWorkspaceViewModel,
        onDismiss: @escaping () -> Void = {}
    ) -> some View {
        self.modifier(CameraSheetRouter(viewModel: viewModel, onDismiss: onDismiss))
    }
}
