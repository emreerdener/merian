import AVFoundation
import CoreLocation
import SwiftUI

struct OnboardingView: View {
    // MARK: - State Dependencies
    @State private var viewModel = OnboardingViewModel()
    @State private var locationManagerDelegate = LocationPermissionDelegate()
    
    // MARK: - Visual Layout
    var body: some View {
        ZStack {
            // 1. Background Layer
            Color(uiColor: .systemBackground).ignoresSafeArea()
            
            // 2. Programmatic Step Control (Disables arbitrary swiping)
            Group {
                switch viewModel.currentStep {
                case .welcome:
                    WelcomeStepView { advanceStep() }
                case .camera:
                    CameraPermissionStepView { advanceStep() }
                case .location:
                    LocationPermissionStepView(locationManagerDelegate: locationManagerDelegate) { advanceStep() }
                case .ready:
                    ReadyStepView {
                        viewModel.completeOnboarding() // Triggers root view teardown safely without zero-frame animation artifacts
                    }
                }
            }
            .id(viewModel.currentStep)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
    }
    
    // MARK: - Action Handlers
    private func advanceStep() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            viewModel.advanceStep()
        }
    }
}
