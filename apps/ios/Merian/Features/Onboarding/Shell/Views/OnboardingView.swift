import SwiftUI

struct OnboardingView: View {
    // MARK: - State Dependencies
    @State private var viewModel: OnboardingViewModel
    @State private var consentSaveErrorMessage = ""
    @State private var isShowingConsentSaveError = false

    private let permissions: OnboardingPermissionDependencies
    private let isAmbientAnimationEnabled: @MainActor () -> Bool

    @MainActor
    init() {
        self.init(
            dependencies: .live(),
            permissions: .live
        )
    }

    @MainActor
    init(dependencies: OnboardingDependencies) {
        self.init(
            dependencies: dependencies,
            permissions: .live
        )
    }

    @MainActor
    init(
        dependencies: OnboardingDependencies,
        permissions: OnboardingPermissionDependencies
    ) {
        _viewModel = State(
            initialValue: OnboardingViewModel(dependencies: dependencies)
        )
        self.permissions = permissions
        isAmbientAnimationEnabled = dependencies.isAmbientAnimationEnabled
    }

    // MARK: - Visual Layout
    var body: some View {
        ZStack {
            // 1. Background Layer
            Color(uiColor: .systemBackground).ignoresSafeArea()

            // 2. Persistent Ambient Accent
            OnboardingAmbientGradient(
                isHardwareAnimationEnabled: isAmbientAnimationEnabled
            )

            // 3. Programmatic Step Control (Disables arbitrary swiping)
            Group {
                switch viewModel.currentStep {
                case .welcome:
                    WelcomeStepView {
                        advanceStep(from: .welcome)
                    }
                case .camera:
                    CameraPermissionStepView(
                        requestCameraAccess: permissions.requestCameraAccess
                    ) {
                        advanceStep(from: .camera)
                    }
                case .location:
                    LocationPermissionStepView(
                        requestLocationAccess:
                            permissions.requestLocationAccess
                    ) {
                        advanceStep(from: .location)
                    }
                case .ready:
                    ReadyStepView { analyticsEnabled in
                        do {
                            try viewModel.completeOnboarding(
                                analyticsEnabled: analyticsEnabled
                            ) // Triggers root view teardown safely without zero-frame animation artifacts
                        } catch {
                            consentSaveErrorMessage = error.localizedDescription
                            isShowingConsentSaveError = true
                        }
                    }
                }
            }
            .id(viewModel.currentStep)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .alert(
            "Couldn’t save your choices",
            isPresented: $isShowingConsentSaveError
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "Scanning and analytics remain disabled. \(consentSaveErrorMessage)"
            )
        }
    }

    // MARK: - Action Handlers
    private func advanceStep(from expectedStep: OnboardingStep) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            viewModel.advanceStep(from: expectedStep)
        }
    }
}
