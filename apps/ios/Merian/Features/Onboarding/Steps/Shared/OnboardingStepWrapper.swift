import SwiftUI

// MARK: - Core Feature Presentation Primitive
struct OnboardingStepWrapper: View {
    // MARK: - Visual Asset Matrix
    var imageName: String?
    var iconColor: SwiftUI.Color?
    var iconText: String?
    var iconCornerRadius: CGFloat?

    // MARK: - Typography Context
    let title: String
    let subtitle: String

    // MARK: - Primary Action Binding
    let primaryButtonTitle: String
    let primaryButtonTextColor: SwiftUI.Color
    let primaryButtonColor: SwiftUI.Color
    let primaryAction: () -> Void

    // MARK: - Secondary Action Fallback
    var secondaryButtonTitle: String?
    var secondaryAction: (() -> Void)?

    // MARK: - Subviews

    private var primaryButton: some View {
        Button(action: primaryAction) {
            Text(primaryButtonTitle)
                .font(.headline)
                .foregroundColor(primaryButtonTextColor)
                .frame(maxWidth: .infinity)
                .padding()
                .background(primaryButtonColor)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var illustration: some View {
        if let imageName {
            OnboardingIllustration(imageName: imageName)
        } else if let iconColor, let iconCornerRadius, let iconText {
            Rectangle()
                .fill(iconColor)
                .frame(width: 300, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous))
                .overlay(Text(iconText).foregroundColor(SwiftUI.Color.gray))
                .frame(width: OnboardingIllustration.stageSize, height: OnboardingIllustration.stageSize)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Visual Layout
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    // 1. Central Graphic Core
                    illustration
                        .padding(.top, OnboardingIllustration.topPadding)

                    // 2. Messaging Display
                    VStack(spacing: 16) {
                        Text(title)
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(SwiftUI.Color.primary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(subtitle)
                            .font(.body)
                            .foregroundColor(SwiftUI.Color.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 24)

                    Spacer(minLength: 24)

                    // 3. Action Buttons
                    if let secondaryTitle = secondaryButtonTitle, let secondaryAction = secondaryAction {
                        VStack(spacing: 24) {
                            primaryButton
                            Button(action: secondaryAction) {
                                Text(secondaryTitle)
                                    .font(.subheadline)
                                    .foregroundColor(SwiftUI.Color.secondary)
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                    } else {
                        primaryButton
                            .padding(.horizontal, 32)
                            .padding(.bottom, 64)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
