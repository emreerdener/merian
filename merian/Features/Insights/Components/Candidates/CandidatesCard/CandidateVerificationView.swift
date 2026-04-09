import SwiftUI

/// Surface presented when the AI has low confidence and there are NO alternative candidates
/// for the user to review. It prompts the user to either confirm the AI's match or flag it.
struct CandidateVerificationView: View {
    let confirmButtonTitle: String
    let onConfirm: () -> Void
    var onFlagIssue: (() -> Void)?
    var onRefineScan: (() -> Void)?
    let onDismiss: () -> Void
    var showDismissButton: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 32) {
                // Content Heading
                VStack(spacing: 8) {                        
                    Text("Verify identification")
                        .font(.system(.title2).weight(.bold))
                        .foregroundColor(.primary)
                    Text("The model had low confidence on this match")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .multilineTextAlignment(.center)
                
                // Action Buttons
                VStack(spacing: 12) {
                    SlideToConfirm(label: "Confirm identification", onConfirm: onConfirm)
                    
                     Button {
                        HapticManager.shared.triggerMediumPulse()
                        onFlagIssue?()
                    } label: {
                        Text("Flag as incorrect")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if showDismissButton {
                Button {
                    HapticManager.shared.triggerLightImpact()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(colorScheme == .dark ? Color.black.opacity(0.5) : Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color(UIColor.separator), lineWidth: 0.5)
        )
    }
}

#if DEBUG
#Preview {
    CandidateVerificationView(
        confirmButtonTitle: "Confirm viceroy",
        onConfirm: {},
        onFlagIssue: {},
        onDismiss: {}
    )
    .padding()
}
#endif
