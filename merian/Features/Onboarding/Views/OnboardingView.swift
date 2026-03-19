import SwiftUI
import AVFoundation
import CoreLocation
import RiveRuntime



struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @StateObject private var locationManagerDelegate = LocationPermissionDelegate()
    
    var body: some View {
        ZStack {
            // Background Layer
            Color.black.ignoresSafeArea()
            
            // Programmatic Step Control (Disables arbitrary swiping)
            switch viewModel.currentStep {
            case .welcome:
                WelcomeStepView { advanceStep() }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            case .camera:
                CameraPermissionStepView { advanceStep() }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            case .location:
                LocationPermissionStepView(locationManagerDelegate: locationManagerDelegate) { advanceStep() }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            case .photoLibrary:
                PhotoLibraryPermissionStepView { advanceStep() }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            case .ready:
                ReadyStepView {
                    viewModel.completeOnboarding() // Triggers root view teardown safely without zero-frame animation artifacts
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
    }
    
    private func advanceStep() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            viewModel.advanceStep()
        }
    }
}


