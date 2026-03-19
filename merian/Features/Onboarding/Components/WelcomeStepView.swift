import SwiftUI
import RiveRuntime

struct WelcomeStepView: View {
    let onNext: () -> Void
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            // TODO: Drop RiveViewModel file here
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 250, height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(Text("Welcome Rive Animation").foregroundColor(.gray))
            
            VStack(spacing: 16) {
                Text("Your Magical\nMagnifying Glass")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("Merian identifies the living world around you with scientific accuracy. Point at any plant or animal to begin.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            
            Button(action: onNext) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 64)
        }
    }
}
