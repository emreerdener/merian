import SwiftUI

struct ViewfinderHintBanner: View {
    @EnvironmentObject var vui: ViewfinderIntelligence
    @State private var showInitialPrompt: Bool = true
    
    var body: some View {
        Group {
            if showInitialPrompt && vui.isOptimal {
                Text("Take a photo to identify")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .clipShape(Capsule())
                    .padding(.bottom, 16)
                    .transition(.opacity)
            } else if !vui.isOptimal {
                Text(vui.currentHint.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .clipShape(Capsule())
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showInitialPrompt)
        .animation(.easeInOut(duration: 0.3), value: vui.isOptimal)
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 3_500_000_000) // 3.5 seconds
                withAnimation {
                    showInitialPrompt = false
                }
            }
        }
    }
}
