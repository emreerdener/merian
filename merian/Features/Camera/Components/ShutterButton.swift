import SwiftUI

struct ShutterButton: View {
    let onCapture: () -> Void
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 1)
                .frame(width: 80, height: 80)
            
            Circle()
                .fill(Color.white)
                .frame(width: 72, height: 72)
        }
        .environment(\.colorScheme, .dark)
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            onCapture()
        }
        .padding(.bottom, 32)
    }
}
