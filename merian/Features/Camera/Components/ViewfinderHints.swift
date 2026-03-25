import SwiftUI

struct ViewfinderHints: View {
    @Environment(ViewfinderIntelligence.self) var vui
    @State private var showInitialPrompt: Bool = true
    /// Stays false until the initial prompt has fully faded out, preventing the VUI hint
    /// from cross-fading in while the welcome text is still visible on screen.
    @State private var vuiHintsAllowed: Bool = false

    var body: some View {
        Group {
            if showInitialPrompt {
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
            } else if vuiHintsAllowed && !vui.isOptimal {
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
                try? await Task.sleep(nanoseconds: 3_500_000_000) // 3.5 s
                withAnimation { showInitialPrompt = false }
                // Wait for the fade-out to finish before allowing VUI hints to appear.
                try? await Task.sleep(nanoseconds: 350_000_000) // 0.35 s
                vuiHintsAllowed = true
            }
        }
    }
}
