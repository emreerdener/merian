import SwiftUI
import RiveRuntime

struct BaseOnboardingStepView: View {
    let iconColor: Color
    let iconText: String
    let iconCornerRadius: CGFloat
    
    let title: String
    let subtitle: String
    
    let primaryButtonTitle: String
    let primaryButtonTextColor: Color
    let primaryButtonColor: Color
    let primaryAction: () -> Void
    
    var secondaryButtonTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // TODO: Drop RiveViewModel file here
            Rectangle()
                .fill(iconColor)
                .frame(width: 250, height: 250)
                .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous))
                .overlay(Text(iconText).foregroundColor(.gray))
            
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            
            if let secondaryTitle = secondaryButtonTitle, let secondaryAction = secondaryAction {
                VStack(spacing: 24) {
                    Button(action: primaryAction) {
                        Text(primaryButtonTitle)
                            .font(.headline)
                            .foregroundColor(primaryButtonTextColor)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(primaryButtonColor)
                            .clipShape(Capsule())
                    }
                    
                    Button(action: secondaryAction) {
                        Text(secondaryTitle)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            } else {
                Button(action: primaryAction) {
                    Text(primaryButtonTitle)
                        .font(.headline)
                        .foregroundColor(primaryButtonTextColor)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(primaryButtonColor)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 64)
            }
        }
    }
}
