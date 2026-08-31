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
    @State private var viewModel: ConfidencePresentationViewModel
    @State private var shimmerPhase: CGFloat = -1.0
    @State private var activeDetent: PresentationDetent = .fraction(0.65)
    @State private var allowedDetents: Set<PresentationDetent> = [.fraction(0.65), .large]
    @State private var iconRotation: Double = 0.0
    @State private var textHuePhase: Double = 0.0

    init(
        confidenceScore: Double?,
        inferenceTier: String?,
        userIdentificationOverride: String? = nil,
        userConfirmedIdentification: Bool = false,
        isFlagged: Bool = false,
        aiScientificName: String? = nil,
        onAskCommunity: (() -> Void)? = nil,
        analyzingPhrase: String? = nil,
        onAnalyzingTap: (() -> Void)? = nil,
        dependencies: ConfidenceReviewDependencies = .live
    ) {
        self.confidenceScore = confidenceScore
        self.inferenceTier = inferenceTier
        self.userIdentificationOverride = userIdentificationOverride
        self.userConfirmedIdentification = userConfirmedIdentification
        self.isFlagged = isFlagged
        self.aiScientificName = aiScientificName
        self.onAskCommunity = onAskCommunity
        self.analyzingPhrase = analyzingPhrase
        self.onAnalyzingTap = onAnalyzingTap
        self._viewModel = State(
            initialValue: ConfidencePresentationViewModel(
                dependencies: dependencies
            )
        )
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

    private var presentation: ConfidenceBadgePresentation {
        ConfidenceBadgePresentation.resolve(
            confidenceScore: confidenceScore,
            inferenceTier: inferenceTier,
            hasUserOverride: userIdentificationOverride != nil,
            isUserConfirmed: userConfirmedIdentification,
            analyzingPhrase: analyzingPhrase
        )
    }

    private func color(
        for style: ConfidenceBadgePresentation.Style
    ) -> Color {
        switch style {
        case .analyzing:
            return .blue
        case .confirmed, .strong:
            return .green
        case .possible:
            return .orange
        case .weak, .unknown:
            return .gray
        }
    }
    
    var body: some View {
        if presentation.isVisible {
            let data = presentation
            let dataColor = color(for: data.style)
            let isAnalyzing = data.isAnalyzing
            let presentedScanId = inferenceEngine.speciesData?.scanId
            let presentedGeneration = inferenceEngine.scanPresentationGeneration
            
            Button(action: {
                if isAnalyzing {
                    onAnalyzingTap?()
                    return
                }
                guard let presentedScanId,
                      viewModel.presentExplanation(
                          subject: IdentificationReviewSubject(
                              scanId: presentedScanId,
                              presentationGeneration: presentedGeneration
                          ),
                          in: inferenceEngine
                      ) else {
                    return
                }
                activeDetent = .fraction(0.65)
                allowedDetents = [.fraction(0.65), .large]
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
                                    colors: [dataColor.opacity(0.9), dataColor.opacity(0.8)],
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
                        .strokeBorder(isAnalyzing ? Color.primary.opacity(0.2) : dataColor.opacity(0.2), lineWidth: 1)
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
            // Preserve the native Button accessibility node. Re-composing this control with
            // children: .ignore changes where an outer accessibilityIdentifier is exposed and
            // makes UI automation unable to find the scanning badge as a Button.
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
            .sheet(
                isPresented: explanationPresentedBinding,
                onDismiss: resumePendingExplanationDismissalAction
            ) {
                if let subject = viewModel.explanationSubject {
                    ConfidenceExplanationSheet(
                        scanId: subject.scanId,
                        presentationGeneration: subject.presentationGeneration,
                        confidenceScore: confidenceScore,
                        inferenceTier: inferenceTier,
                        userIdentificationOverride: userIdentificationOverride,
                        userConfirmedIdentification: userConfirmedIdentification,
                        isFlagged: isFlagged,
                        aiScientificName: aiScientificName,
                        onAskCommunity: onAskCommunity,
                        onRequestDismissalAction: { action in
                            viewModel.stageDismissalAction(action)
                        },
                        dependencies: viewModel.childDependencies
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
        let expectedSubject = viewModel.explanationSubject
        return Binding(
            get: {
                guard viewModel.isExplanationPresented,
                      let expectedSubject,
                      expectedSubject.matches(viewModel.explanationSubject) else {
                    return false
                }
                return viewModel.isCurrent(
                    expectedSubject,
                    in: inferenceEngine
                )
            },
            set: { isPresented in
                guard !isPresented else { return }
                guard let expectedSubject else { return }
                viewModel.dismissExplanation(ownedBy: expectedSubject)
            }
        )
    }

    private func resumePendingExplanationDismissalAction() {
        guard let currentScanId = inferenceEngine.speciesData?.scanId else {
            viewModel.invalidateExplanation()
            return
        }
        let currentSubject = IdentificationReviewSubject(
            scanId: currentScanId,
            presentationGeneration: inferenceEngine.scanPresentationGeneration
        )
        guard let action = viewModel.takePendingDismissalAction(
            matching: currentSubject
        ) else { return }

        switch action {
        case .askCommunity:
            onAskCommunity?()
        case .refineScan(_, let initialDescription):
            viewModel.requestRefinementRoute(
                scanId: action.context.scanId,
                initialDescription: initialDescription
            )
        }
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
