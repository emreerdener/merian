import SwiftUI

struct CameraSheetRouter: ViewModifier {
    @Bindable var viewModel: CameraViewModel
    
    func body(content: Content) -> some View {
        content
            .sheet(item: $viewModel.activeSheet, onDismiss: {
                viewModel.handleSheetDismiss()
            }) { sheet in
                Group {
                    switch sheet {
                    case .insight:
                        InsightSheetView(isPresented: Binding(
                            get: { viewModel.activeSheet == .insight },
                            set: { if !$0 && viewModel.activeSheet == .insight { viewModel.activeSheet = nil } }
                        ))
                    case .paywall:
                        PaywallView()
                    case .profile:
                        ProfileView()
                    case .scans:
                        ScansSheetView(isInsightSheetOpen: Binding(
                            get: { viewModel.activeSheet == .insight },
                            set: { if $0 { viewModel.activeSheet = .insight } else if viewModel.activeSheet == .insight { viewModel.activeSheet = nil } }
                        ))
                    }
                }
                .presentationDragIndicator(.hidden)
                .onAppear {
                    viewModel.handleSheetAppear()
                }
            }
    }
}

extension View {
    func cameraSheetRouter(viewModel: CameraViewModel) -> some View {
        self.modifier(CameraSheetRouter(viewModel: viewModel))
    }
}
