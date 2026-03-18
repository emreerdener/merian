import SwiftUI

struct ViewfinderHintBanner: View {
    @EnvironmentObject var vui: ViewfinderIntelligence
    
    var body: some View {
        if !vui.isOptimal {
            Text(vui.currentHint.rawValue)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .clipShape(Capsule())
                .padding(.bottom, 16)
        }
    }
}
