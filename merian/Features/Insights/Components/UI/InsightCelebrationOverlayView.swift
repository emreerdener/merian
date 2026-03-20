import SwiftUI

struct InsightCelebrationOverlayView: View {
    let commonName: String
    @Binding var showCelebration: Bool
    
    var body: some View {
        if showCelebration {
            VStack {
                NewDiscoveryCelebrationView(
                    commonName: commonName,
                    onDismiss: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showCelebration = false
                        }
                    }
                )
                .padding(.top, 16)
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(100)
        }
    }
}
