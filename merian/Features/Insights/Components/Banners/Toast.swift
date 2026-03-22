import SwiftUI

struct Toast: View {
    let message: String
    
    var body: some View {
        VStack {
            Spacer()
            Text(message)
                .font(.footnote)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .colorScheme(.dark)
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                .padding(.bottom, 60)
                // Transitions must be applied at the root scope of the component appearing/disappearing
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
        }
    }
}
