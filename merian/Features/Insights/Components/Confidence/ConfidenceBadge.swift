import SwiftUI

struct ConfidenceBadge: View {
    let confidenceScore: Double?
    let inferenceTier: String?
    @State private var shimmerPhase: CGFloat = -1.0
    @State private var isShowingExplanation = false
    @State private var activeDetent: PresentationDetent = .fraction(0.65)
    @State private var allowedDetents: Set<PresentationDetent> = [.fraction(0.65), .large]
    
    private struct BadgePayload {
        let label: String
        let color: Color
        let icon: String
    }
    
    private var badgeData: BadgePayload {
        guard let score = confidenceScore else { return BadgePayload(label: "Unknown", color: .gray, icon: "questionmark") }
        let bands = MerianConfig.confidenceBands(forInferenceTier: inferenceTier)
        switch score {
        case bands.strong...:
            return BadgePayload(label: "Strong match", color: .green, icon: "sparkles.2")
        case bands.possible..<bands.strong:
            return BadgePayload(label: "Possible match", color: .orange, icon: "sparkles.2")
        default:
            return BadgePayload(label: "Weak match", color: .gray, icon: "sparkles.2")
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
                HStack(spacing: 6) {
                    Image(systemName: data.icon)
                        .imageScale(.medium)
                        .frame(width: 16, alignment: .center)
                    Text(data.label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(.subheadline, weight: .bold))
                // Text color pops brightly against the deeply tinted glass
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                // Liquid Glass Background Stack
                .background(
                    ZStack {
                        // Blurred System Glass Foundation
                        Capsule()
                            .fill(.ultraThickMaterial)
                        
                        // Volumetric Color Tint
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [data.color.opacity(0.9), data.color.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Glossy Inner Rim Highlight
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.6), .white.opacity(0.0), .white.opacity(0.2)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.5
                            )
                    }
                )
                // Ambient Static Glass Boundary
                .overlay(
                    Capsule()
                        .strokeBorder(data.color.opacity(0.2), lineWidth: 1)
                )
                // Animated Holographic Glare Sweep
                .overlay(
                    GeometryReader { geo in
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .white.opacity(0.8), location: 0.45),
                                        // Solid, stark white highlight that ignores background saturation
                                        .init(color: .white, location: 0.5),
                                        .init(color: .white.opacity(0.8), location: 0.55),
                                        .init(color: .clear, location: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: max(geo.size.width, 1))
                            .offset(x: shimmerPhase * max(geo.size.width, 1) * 2)
                            .mask(
                                Capsule()
                                    .strokeBorder(lineWidth: 1.5)
                            )
                    }
                )
            }
            .buttonStyle(.plain)
            .task(id: score) {
                while !Task.isCancelled {
                    let randomSleepSeconds = Double.random(in: 4.0...10.0)
                    try? await Task.sleep(for: .seconds(randomSleepSeconds))
                    
                    guard !Task.isCancelled else { break }
                    
                    shimmerPhase = -1.0
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    
                    // Slowed down from 1.8s to 3.5s so it lazily sweeps across the wider capsule
                    withAnimation(.easeOut(duration: 3.5)) {
                        shimmerPhase = 2.5
                    }
                }
            }
            .sheet(isPresented: $isShowingExplanation) {
                ConfidenceExplanationSheet(inferenceTier: inferenceTier)
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
