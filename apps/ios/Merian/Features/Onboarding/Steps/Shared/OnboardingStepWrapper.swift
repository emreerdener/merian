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
    }
}
