import SwiftUI

struct CameraSheetRouter: ViewModifier {
    @Bindable var viewModel: CameraViewModel
    @AppStorage("themeMode") private var themeMode: ThemeMode = .system
    
    func body(content: Content) -> some View {
        content
            .sheet(item: $viewModel.activeSheet) { sheet in
                Group {
                    switch sheet {
                    case .insight:
                        InsightSheetView(isPresented: Binding(
                            get: { viewModel.activeSheet == .insight },
                            set: { if !$0 && viewModel.activeSheet == .insight { viewModel.activeSheet = nil } }
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
    }
}

extension View {
    func cameraSheetRouter(viewModel: CameraViewModel) -> some View {
        self.modifier(CameraSheetRouter(viewModel: viewModel))
    }
}
