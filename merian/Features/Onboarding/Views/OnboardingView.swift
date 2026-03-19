import SwiftUI
import AVFoundation
import CoreLocation
import RiveRuntime

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case camera
    case location
    case ready
}

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var currentStep: OnboardingStep = .welcome
    @StateObject private var locationManagerDelegate = LocationPermissionDelegate()
    
    var body: some View {
        ZStack {
            // Background Layer
            Color.black.ignoresSafeArea()
            
            // Programmatic Step Control (Disables arbitrary swiping)
            switch currentStep {
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
            case .ready:
                ReadyStepView {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        hasCompletedOnboarding = true // Triggers root view teardown
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
    }
    
    private func advanceStep() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
                currentStep = next
            }
        }
    }
}


