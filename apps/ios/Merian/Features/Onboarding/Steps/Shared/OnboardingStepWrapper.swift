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

    // MARK: - Required Agreement
    var termsAgreement: Binding<Bool>?
    var termsURL: URL?
    
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
        .disabled(isPrimaryButtonDisabled)
        .opacity(isPrimaryButtonDisabled ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.2), value: isPrimaryButtonDisabled)
        .accessibilityHint(isPrimaryButtonDisabled ? "Agree to the terms to continue" : "")
    }

    private var isPrimaryButtonDisabled: Bool {
        termsAgreement?.wrappedValue == false
    }

    @ViewBuilder
    private var termsAgreementView: some View {
        if let termsAgreement, let termsURL {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    termsAgreement.wrappedValue.toggle()
                } label: {
                    Label {
                        Text("I agree to the terms")
                            .font(.subheadline.weight(.medium))
                    } icon: {
                        Image(systemName: termsAgreement.wrappedValue ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundStyle(termsAgreement.wrappedValue ? Color.accentColor : Color.secondary)
                    }
                    .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("I agree to the Terms of Service")
                .accessibilityValue(termsAgreement.wrappedValue ? "Selected" : "Not selected")

                Link("View the full Terms of Service", destination: termsURL)
                    .font(.footnote.weight(.semibold))
                    .padding(.leading, 32)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Visual Layout
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // 1. Central Graphic Core
            if let imageName = imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 32)
            } else if let iconColor = iconColor, let iconCornerRadius = iconCornerRadius, let iconText = iconText {
                Rectangle()
                    .fill(iconColor)
                    .frame(width: 300, height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous))
                    .overlay(Text(iconText).foregroundColor(SwiftUI.Color.gray))
            }
            
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
            
            // 3. Agreements and Action Buttons
            VStack(spacing: 24) {
                termsAgreementView
                primaryButton

                if let secondaryTitle = secondaryButtonTitle, let secondaryAction = secondaryAction {
                    Button(action: secondaryAction) {
                        Text(secondaryTitle)
                            .font(.subheadline)
                            .foregroundColor(SwiftUI.Color.secondary)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, secondaryButtonTitle == nil ? 64 : 32)
        }
    }
}
