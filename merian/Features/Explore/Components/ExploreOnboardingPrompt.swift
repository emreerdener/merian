import SwiftUI

struct ExploreOnboardingPrompt: View {
    let onShare: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image("compass")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
            
            VStack(spacing: 12) {
                Text("Join the Merian Community")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("Share your discovery on the Explore feed to contribute to the global archive and help others learn about the natural world.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            VStack(spacing: 24) {
                Button {
                    onShare()
                } label: {
                    Text("Share discovery")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button {
                    onDismiss()
                } label: {
                    Text("Not now")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
