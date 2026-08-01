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

            // 2. Persistent Ambient Accent
            OnboardingAmbientGradient()
            
            // 3. Programmatic Step Control (Disables arbitrary swiping)
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

private struct OnboardingAmbientGradient: View {
    // MARK: - Motion Dependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShifted = false

    private var shouldAnimate: Bool {
        HardwareOrchestrator.shared.isAnimationEnabled && !reduceMotion
    }

    // MARK: - Visual Layout
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let fieldSize = max(width, height * 0.55)

            ZStack {
                ambientBlob(
                    color: Color(red: 0.28, green: 0.68, blue: 1.0),
                    strength: 0.52,
                    diameter: fieldSize * 1.25
                )
                .scaleEffect(
                    x: isShifted ? 0.96 : 1.18,
                    y: isShifted ? 1.16 : 0.92
                )
                .position(
                    x: width * (isShifted ? 0.72 : 0.10),
                    y: height * (isShifted ? 0.14 : 0.06)
                )
                .animation(driftingAnimation(duration: 23), value: isShifted)

                ambientBlob(
                    color: Color(red: 0.58, green: 0.44, blue: 1.0),
                    strength: 0.46,
                    diameter: fieldSize * 1.15
                )
                .scaleEffect(
                    x: isShifted ? 1.20 : 0.94,
                    y: isShifted ? 0.88 : 1.12
                )
                .position(
                    x: width * (isShifted ? 0.28 : 0.86),
                    y: height * (isShifted ? 0.29 : 0.16)
                )
                .animation(driftingAnimation(duration: 29), value: isShifted)

                ambientBlob(
                    color: Color(red: 0.34, green: 0.72, blue: 0.46),
                    strength: 0.38,
                    diameter: fieldSize * 1.05
                )
                .scaleEffect(
                    x: isShifted ? 0.92 : 1.16,
                    y: isShifted ? 1.15 : 0.86
                )
                .position(
                    x: width * (isShifted ? 0.80 : 0.18),
                    y: height * (isShifted ? 0.37 : 0.43)
                )
                .animation(driftingAnimation(duration: 31), value: isShifted)
            }
            .frame(width: width, height: height)
            .blur(radius: 48)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.32),
                        .init(color: .black.opacity(0.8), location: 0.46),
                        .init(color: .clear, location: 0.64)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            updateAnimation(enabled: shouldAnimate)
        }
        .onChange(of: shouldAnimate) { _, isEnabled in
            updateAnimation(enabled: isEnabled)
        }
    }

    // MARK: - Gradient Construction
    private func ambientBlob(color: Color, strength: Double, diameter: CGFloat) -> some View {
        RadialGradient(
            stops: [
                .init(color: color.opacity(strength), location: 0),
                .init(color: color.opacity(strength * 0.76), location: 0.38),
                .init(color: color.opacity(strength * 0.28), location: 0.74),
                .init(color: .clear, location: 1)
            ],
            center: .center,
            startRadius: 0,
            endRadius: diameter * 0.5
        )
        .frame(width: diameter, height: diameter)
    }

    private func driftingAnimation(duration: Double) -> Animation? {
        shouldAnimate
            ? .easeInOut(duration: duration).repeatForever(autoreverses: true)
            : nil
    }

    // MARK: - Animation Control
    private func updateAnimation(enabled: Bool) {
        if enabled {
            isShifted = true
        } else {
            withAnimation(nil) {
                isShifted = false
            }
        }
    }
}
