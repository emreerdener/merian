import SwiftUI

// MARK: - Analyzing Visual Effects
struct AnalyzingVisualEffectsView: View {
    @State private var pulseOpacity: Double = 0.0

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.black)
                .opacity(pulseOpacity)
                .allowsHitTesting(false)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(1)) {
                pulseOpacity = 0.4
            }
        }
    }
}
