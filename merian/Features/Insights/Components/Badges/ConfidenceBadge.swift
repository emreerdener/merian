import SwiftUI

struct ConfidenceBadge: View {
    let confidenceScore: Double?
    @State private var shimmerPhase: CGFloat = -1.0
    @State private var isShowingExplanation = false
    @State private var activeDetent: PresentationDetent = .fraction(0.65)
    @State private var allowedDetents: Set<PresentationDetent> = [.fraction(0.65), .large]
    
    // Natively interprets raw Float outputs into deeply semantic structural thresholds
    private var badgeData: (label: String, color: Color, icon: String) {
        guard let score = confidenceScore else { return ("Unknown", .gray, "questionmark") }
        switch score {
        case 0.95...:
            return ("High confidence", Color(red: 0.11, green: 0.52, blue: 0.28), "sparkles.2")
        case 0.85..<0.95:
            return ("Confident", Color(red: 0.11, green: 0.52, blue: 0.28), "sparkles.2")
        case 0.70..<0.85:
            return ("Educated guess", .orange, "sparkles.2")
        default:
            return ("Low confidence", .red, "sparkles.2")
        }
    }
    
    var body: some View {
        if let score = confidenceScore, score > 0 {
            let data = badgeData
            
            Button(action: {
                HapticManager.shared.triggerSheetSpring()
                activeDetent = .fraction(0.65)
                allowedDetents = [.fraction(0.65), .large]
                isShowingExplanation = true
            }) {
                Badge(
                    text: data.label,
                    color: data.color,
                    icon: data.icon,
                    isFilled: true
                )
                // Ambient Static Glass Boundary
                .overlay(
                    Capsule()
                        .strokeBorder(data.color.opacity(0.2), lineWidth: 1.5)
                )
                // Animated Holographic Glare Sweep
                .overlay(
                    GeometryReader { geo in
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .white.opacity(0.9), location: 0.5),
                                        .init(color: .clear, location: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: geo.size.width)
                            .offset(x: shimmerPhase * geo.size.width * 2)
                            .blendMode(.screen)
                            .mask(
                                Capsule().stroke(lineWidth: 1.5)
                            )
                    }
                )
                // Stacked shadows: structural drop + ambient semantic glow
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                .shadow(color: data.color.opacity(0.25), radius: 12, x: 0, y: 0)
            }
            .buttonStyle(.plain)
            .onAppear {
                withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) {
                    shimmerPhase = 2.5
                }
            }
            .sheet(isPresented: $isShowingExplanation) {
                ConfidenceExplanationSheet()
                    .presentationDetents(allowedDetents, selection: $activeDetent)
                    .presentationCornerRadius(32)
                    .presentationBackground(.ultraThinMaterial)
                    .presentationDragIndicator(.visible)
                    // Dynamically strips the mid-way detent once fully expanded native Apple hack!
                    .onChange(of: activeDetent) { _, newDetent in
                        if newDetent == .large {
                            allowedDetents = [.large]
                        }
                    }
            }
        }
    }
}


