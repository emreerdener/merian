import SwiftUI
import RiveRuntime

struct ReadyStepView: View {
    let onFinish: () -> Void
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            // TODO: Drop RiveViewModel file here
            Rectangle()
                .fill(Color.yellow.opacity(0.1))
                .frame(width: 250, height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(Text("Success Rive Animation").foregroundColor(.gray))
            
            VStack(spacing: 16) {
                Text("You're ready")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("Let's step outside and discover something wild.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            
            Button(action: onFinish) {
                Text("Start Scanning")
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
