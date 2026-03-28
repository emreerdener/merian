import SwiftUI

struct ModelTierBanner: View {
    let confidenceScore: Double?
    @State private var phase: Double = 0.0
    
    var body: some View {
        if !RevenueCatManager.shared.isProActive, let score = confidenceScore {
            let bands = MerianConfig.confidenceBands(for: false)
            if score >= bands.possible && score < bands.strong {
                Button(action: {
                    AppEventPublisher.shared.send(.triggerPaywall)
                }) {
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.footnote.weight(.bold))
                        
                        Text("Get higher confidence with Pro")
                            .font(.footnote.weight(.semibold))
                            
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 2)
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.indigo, .purple, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                AngularGradient(
                                    colors: [.indigo, .purple, .pink, .indigo],
                                    center: .center,
                                    angle: .degrees(phase)
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: .purple.opacity(0.15), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .onAppear {
                    withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                        phase = 360.0
                    }
                }
            }
        }
    }
}
