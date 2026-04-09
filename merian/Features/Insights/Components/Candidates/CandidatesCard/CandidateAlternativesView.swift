import SwiftUI

/// Surface presented when there ARE alternative candidates for the user to review.
/// The user can either confirm the primary match or open the alternatives swipe modal.
struct CandidateAlternativesView: View {
    let candidates: [IdentificationCandidate]
    let confirmButtonTitle: String
    let isWeakMatch: Bool
    let onReviewAlternatives: () -> Void
    let onConfirm: () -> Void
    var onRefineScan: (() -> Void)?
    let onDismiss: () -> Void
    var showDismissButton: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: candidates.count > 1 ? 48 : 24) {
                // Visual Graphic stack
                ZStack {
                    let displayCandidates = Array(candidates.prefix(2))
                    let isPair = displayCandidates.count == 2
                    
                    ForEach(Array(displayCandidates.enumerated().reversed()), id: \.offset) { index, candidate in
                        let rotation: Double = isPair ? (index == 0 ? -5 : 5) : .zero
                        let offsetX: CGFloat = isPair ? (index == 0 ? -16 : 16) : .zero
                        let offsetY: CGFloat = isPair ? (index == 0 ? 0 : 12) : .zero

                        FlayedCandidateThumbnail(candidate: candidate)
                            .rotationEffect(.degrees(rotation))
                            .offset(x: offsetX, y: offsetY)
                            .zIndex(-Double(index))
                            .visualEffect { content, proxy in
                                let scrollOffset = proxy.frame(in: .global).minY
                                let wave = sin(scrollOffset / 200.0)
                                
                                // Subtle fan out effect from the bottom center
                                let rotationWiggle = Double(wave) * (index == 0 ? -3.0 : 3.0)
                                
                                return content
                                    .rotationEffect(.degrees(rotationWiggle), anchor: .bottom)
                            }
                    }
                }
                .padding(.top, 8)
                .onTapGesture(perform: onReviewAlternatives)

                VStack(spacing: 24) {
                    // Content Heading
                    VStack(spacing: 8) {
                        Text("\(candidates.count) \(isWeakMatch ? "possible" : "close") \(candidates.count == 1 ? "match" : "matches") found")
                            .font(.system(.title2).weight(.bold))
                            .foregroundColor(.primary)
                        Text("Other species the model also considered")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    // Action Buttons
                    VStack(spacing: 16) {
                        Button {
                            HapticManager.shared.triggerSelectionPulse()
                            onReviewAlternatives()
                        } label: {
                            Text("Review alternatives")
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    ZStack {
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                        Capsule()
                                            .fill(Color.green.opacity(0.75))
                                    }
                                )
                                .foregroundColor(.white)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
                                        .blendMode(.overlay)
                                )
                        }
                        .buttonStyle(.plain)
                        
                        // Surface the quick-confirm when contained inside the confidence sheet
                        if !showDismissButton {
                            SlideToConfirm(label: "Confirm species", onConfirm: onConfirm)
                        }
                    }
                }
            }

            if showDismissButton {
                Button {
                    HapticManager.shared.triggerLightImpact()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(colorScheme == .dark ? Color.black.opacity(0.5) : Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color(UIColor.separator), lineWidth: 0.5)
        )
    }
}

#if DEBUG
#Preview {
    CandidateAlternativesView(
        candidates: [
            IdentificationCandidate(scientificName: "Limenitis archippus", commonName: "Viceroy", confidenceScore: 0.71)
        ],
        confirmButtonTitle: "Confirm Danaus plexippus",
        isWeakMatch: true,
        onReviewAlternatives: {},
        onConfirm: {},
        onDismiss: {}
    )
    .padding()
}
#endif
