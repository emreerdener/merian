import SwiftUI

struct ConfidenceBadge: View {
    @Environment(InferenceEngine.self) private var inferenceEngine

    let confidenceScore: Double?
    let inferenceTier: String?
    var userIdentificationOverride: String?
    var userConfirmedIdentification: Bool = false
    var isFlagged: Bool = false
    var aiScientificName: String?
    var onAskCommunity: (() -> Void)?
    /// When set, the badge shows an analyzing state with this phrase as its label.
    /// The explanation sheet is suppressed while analyzing.
    var analyzingPhrase: String?
    var onAnalyzingTap: (() -> Void)?
    @State private var shimmerPhase: CGFloat = -1.0
    @State private var isShowingExplanation = false
    @State private var explanationScanId: String?
    @State private var explanationGeneration: UInt64?
    @State private var activeDetent: PresentationDetent = .fraction(0.65)
    @State private var allowedDetents: Set<PresentationDetent> = [.fraction(0.65), .large]
    @State private var iconRotation: Double = 0.0
    @State private var textHuePhase: Double = 0.0

    private struct BadgePayload {
        let label: String
        let color: Color
        let icon: String
    }

    // A rich, mesmerizing primary gradient for the AI inference state
    private var aiGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.25, green: 0.55, blue: 1.0),   // AI Blue
                Color(red: 0.55, green: 0.25, blue: 1.0),   // AI Purple
                Color(red: 0.95, green: 0.35, blue: 0.65)   // AI Pink
            ],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
    }

    private var badgeData: BadgePayload {
        if let phrase = analyzingPhrase {
            let label = phrase.hasSuffix("...") ? phrase : phrase + "..."
            return BadgePayload(label: label, color: .blue, icon: "sparkle")
        }
        if userIdentificationOverride != nil || userConfirmedIdentification {
            return BadgePayload(label: "Confirmed", color: .green, icon: "checkmark.circle.fill")
        }
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
        if analyzingPhrase != nil || userIdentificationOverride != nil || userConfirmedIdentification || (confidenceScore ?? 0) > 0 {
            let data = badgeData
            let isAnalyzing = analyzingPhrase != nil
            let presentedScanId = inferenceEngine.speciesData?.scanId
            let presentedGeneration = inferenceEngine.scanPresentationGeneration
            
            Button(action: {
                if isAnalyzing {
                    onAnalyzingTap?()
                    return
                }
                guard let presentedScanId,
                      inferenceEngine.scanPresentationGeneration == presentedGeneration,
                      inferenceEngine.speciesData?.scanId?
                        .caseInsensitiveCompare(presentedScanId) == .orderedSame else {
                    return
                }
                HapticManager.shared.triggerHeavyImpact(intensity: 1.0)
                activeDetent = .fraction(0.65)
                allowedDetents = [.fraction(0.65), .large]
                explanationScanId = presentedScanId
                explanationGeneration = presentedGeneration
                isShowingExplanation = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: data.icon)
                        .imageScale(.medium)
                        .frame(width: 16, alignment: .center)
                        .rotationEffect(.degrees(isAnalyzing ? iconRotation : 0))
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isAnalyzing)
                    RevealText(text: data.label)
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: data.label)
                .font(.system(.subheadline, weight: .bold))
                // Mesmerizing gradient applies across the whole stack and shifts colors in lock-step natively
                .foregroundStyle(isAnalyzing ? AnyShapeStyle(aiGradient) : AnyShapeStyle(Color.white))
                .hueRotation(.degrees(textHuePhase))
                .shadow(color: isAnalyzing ? .clear : .black.opacity(0.15), radius: 2, x: 0, y: 1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                // Liquid Glass Background Stack
                .background(
                    ZStack {
                        // Blurred System Glass Foundation
                        Capsule()
                            .fill(.ultraThickMaterial)
                            .opacity(isAnalyzing ? 0 : 1)
                        
                        // Volumetric Color Tint
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [data.color.opacity(0.9), data.color.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .opacity(isAnalyzing ? 0 : 1)
                        
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
                            .opacity(isAnalyzing ? 0 : 1)
                    }
                )
                // Ambient Static Glass Boundary
                .overlay(
                    Capsule()
                        .strokeBorder(isAnalyzing ? Color.primary.opacity(0.2) : data.color.opacity(0.2), lineWidth: 1)
                )
                // Canvas keeps the animated glare inside one fixed render surface. A translated
                // SwiftUI child can enlarge its ancestor's accessibility frame even when clipped.
                .overlay {
                    if !isAnalyzing {
                        BadgeGlareSweep(phase: shimmerPhase)
                    }
                }
                // Smoothly animate the fill transition when analysis finishes
                .animation(.easeInOut(duration: 0.4), value: isAnalyzing)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(data.label))
            .task(id: isAnalyzing) {
                guard !isAnalyzing else {
                    shimmerPhase = -1.0
                    return
                }
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
            .task(id: isAnalyzing) {
                if isAnalyzing {
                    // Start smooth, continuous color shift instead of a full 360 rainbow roll
                    withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                        textHuePhase = 45.0
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.5)) {
                        textHuePhase = 0.0
                    }
                }
                
                guard isAnalyzing else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2.0))
                    guard !Task.isCancelled else { break }
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.45)) {
                        iconRotation += 360
                    }
                }
            }
            .sheet(isPresented: explanationPresentedBinding) {
                if let explanationScanId,
                   let explanationGeneration {
                    ConfidenceExplanationSheet(
                        scanId: explanationScanId,
                        presentationGeneration: explanationGeneration,
                        confidenceScore: confidenceScore,
                        inferenceTier: inferenceTier,
                        userIdentificationOverride: userIdentificationOverride,
                        userConfirmedIdentification: userConfirmedIdentification,
                        isFlagged: isFlagged,
                        aiScientificName: aiScientificName,
                        onAskCommunity: onAskCommunity
                    )
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

    private var explanationPresentedBinding: Binding<Bool> {
        let expectedScanId = explanationScanId
        let expectedGeneration = explanationGeneration
        return Binding(
            get: {
                guard isShowingExplanation,
                      let expectedScanId,
                      let expectedGeneration,
                      explanationScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      explanationGeneration == expectedGeneration else {
                    return false
                }
                return inferenceEngine.scanPresentationGeneration ==
                    expectedGeneration &&
                    inferenceEngine.speciesData?.scanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame
            },
            set: { isPresented in
                guard !isPresented else { return }
                guard let expectedScanId,
                      let expectedGeneration,
                      explanationScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      explanationGeneration == expectedGeneration else {
                    return
                }
                isShowingExplanation = false
                explanationScanId = nil
                explanationGeneration = nil
            }
        )
    }
}

// MARK: - Bounded Holographic Glare

/// Draws rather than lays out the moving highlight. Canvas commands never contribute translated
/// child frames to the surrounding Button's hit-testing or accessibility geometry.
private struct BadgeGlareSweep: View {
    let phase: CGFloat

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            let bounds = CGRect(origin: .zero, size: size)
                .insetBy(dx: 0.75, dy: 0.75)
            let capsule = Path(
                roundedRect: bounds,
                cornerRadius: max(bounds.height / 2, 0)
            )
            let travelX = phase * size.width * 2
            let gradient = Gradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .white.opacity(0.8), location: 0.45),
                .init(color: .white, location: 0.5),
                .init(color: .white.opacity(0.8), location: 0.55),
                .init(color: .clear, location: 1.0)
            ])

            context.stroke(
                capsule,
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: travelX, y: size.height),
                    endPoint: CGPoint(x: travelX + size.width, y: 0)
                ),
                lineWidth: 1.5
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Bounded Text Transition

/// Retains text identity while fading label changes without translated mask geometry.
private struct RevealText: View {
    let text: String

    var body: some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.35), value: text)
    }
}
