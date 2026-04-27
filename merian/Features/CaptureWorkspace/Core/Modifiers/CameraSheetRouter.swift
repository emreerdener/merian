import SwiftUI

struct CameraSheetRouter: ViewModifier {
    @Bindable var viewModel: CaptureWorkspaceViewModel
    @AppStorage("themeMode") private var themeMode: ThemeMode = .system
    @State private var showNotificationPrompt = false
    @Environment(InferenceEngine.self) var inferenceEngine
    
    func body(content: Content) -> some View {
        content
            .sheet(item: $viewModel.activeSheet) { sheet in
                Group {
                    switch sheet {
                    case .insight:
                        InsightSheetView(isPresented: Binding(
                            get: { viewModel.activeSheet == .insight },
                            set: { 
                                if !$0 && viewModel.activeSheet == .insight { 
                                    viewModel.activeSheet = nil 
                                    if !UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasPromptedForNotificationsPostIdent) {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            self.showNotificationPrompt = true
                                            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasPromptedForNotificationsPostIdent)
                                        }
                                    }
                                } 
                            }
                        ), inferenceEngine: inferenceEngine)
                        .onAppear {
                            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.hasUnseenScan)
                            PushNotificationManager.shared.setBadgeCount(0)
                        }
                    case .paywall:
                        PaywallView()
                    case .profile:
                        ProfileView()
                    case .explore:
                        ExploreView(initialPostId: viewModel.pendingExplorePostId)
                            .id(viewModel.explorePresentationIdentity)
                            .onDisappear {
                                viewModel.pendingExplorePostId = nil
                            }
                    case .scans:
                        ScansSheetView(isInsightSheetOpen: Binding(
                            get: { viewModel.activeSheet == .insight },
                            set: { if $0 { viewModel.activeSheet = .insight } else if viewModel.activeSheet == .insight { viewModel.activeSheet = nil } }
                        ))
                        .onAppear {
                            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.hasUnseenScan)
                            PushNotificationManager.shared.setBadgeCount(0)
                        }
                    }
                }
                .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $showNotificationPrompt) {
                PostIdentificationNotificationSheetView { granted in
                    UserDefaults.standard.set(granted, forKey: UserDefaultsKeys.isPushNotificationsEnabled)
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
