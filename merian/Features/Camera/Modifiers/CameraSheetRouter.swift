import SwiftUI

struct CameraSheetRouter: ViewModifier {
    @Bindable var viewModel: CameraViewModel
    @AppStorage("themeMode") private var themeMode: ThemeMode = .system
    @State private var showNotificationPrompt = false
    
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
                        ))
                        .onAppear {
                            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.hasUnseenScan)
                            PushNotificationManager.shared.setBadgeCount(0)
                        }
                    case .paywall:
                        PaywallView()
                    case .profile:
                        ProfileView()
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
                PostIdentificationNotificationSheetView {
                    showNotificationPrompt = false
                }
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.hidden)
            }
    }
}

extension View {
    func cameraSheetRouter(viewModel: CameraViewModel) -> some View {
        self.modifier(CameraSheetRouter(viewModel: viewModel))
    }
}
