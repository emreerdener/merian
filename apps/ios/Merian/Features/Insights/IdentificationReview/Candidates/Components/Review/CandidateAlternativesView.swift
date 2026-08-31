import SwiftUI

/// Surface presented when there ARE alternative candidates for the user to review.
/// The user can either confirm the primary match or open the alternatives swipe modal.
struct CandidateAlternativesView: View {
    let candidates: [IdentificationCandidate]
    let confirmButtonTitle: String
    let isWeakMatch: Bool
    let onReviewAlternatives: () -> Void
    let onConfirm: () -> Void
    let onDismiss: () -> Void
    var showDismissButton: Bool = true
    let imageDependencies: SimilarSpeciesImageDependencies
    let feedback: IdentificationReviewFeedbackDependencies

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content

            if showDismissButton {
                dismissButton
            }
        }
        .padding(20)
        .background(cardBackground)
        .overlay(cardBorder)
    }

    private var displayCandidates: [IdentificationCandidate] {
        Array(candidates.prefix(2))
    }

    private var isPairDisplay: Bool {
        displayCandidates.count == 2
    }

    private var content: some View {
        VStack(spacing: candidates.count > 1 ? 48 : 24) {
            candidateGraphicStack

            VStack(spacing: 24) {
                heading
                actionButtons
            }
        }
    }

    private var candidateGraphicStack: some View {
        ZStack {
            ForEach(Array(displayCandidates.enumerated().reversed()), id: \.offset) { index, candidate in
                thumbnail(candidate, at: index)
            }
        }
        .padding(.top, 8)
        .onTapGesture(perform: onReviewAlternatives)
    }

    private func thumbnail(_ candidate: IdentificationCandidate, at index: Int) -> some View {
        let rotation: Double = isPairDisplay ? (index == 0 ? -5 : 5) : 0
        let offsetX: CGFloat = isPairDisplay ? (index == 0 ? -16 : 16) : 0
        let offsetY: CGFloat = isPairDisplay ? (index == 0 ? 0 : 12) : 0

        return FlayedCandidateThumbnail(
            candidate: candidate,
            imageDependencies: imageDependencies
        )
            .rotationEffect(.degrees(rotation))
            .offset(x: offsetX, y: offsetY)
            .zIndex(-Double(index))
            .visualEffect { content, proxy in
                let scrollOffset = proxy.frame(in: .global).minY
                let wave = sin(scrollOffset / 200.0)
                let rotationWiggle = Double(wave) * (index == 0 ? -3.0 : 3.0)

                return content
                    .rotationEffect(.degrees(rotationWiggle), anchor: .bottom)
            }
    }

    private var heading: some View {
        VStack(spacing: 8) {
            Text(headingTitle)
                .font(.system(.title2).weight(.bold))
                .foregroundColor(.primary)
            Text("Other species the model also considered")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    private var headingTitle: String {
        let noun = candidates.count == 1 ? "alternative identification" : "alternative identifications"
        return "\(candidates.count) \(noun)"
    }

    private var actionButtons: some View {
        VStack(spacing: 16) {
            reviewAlternativesButton
            SlideToConfirm(label: confirmButtonTitle, onConfirm: onConfirm)
        }
    }

    private var reviewAlternativesButton: some View {
        Button {
            feedback.selection()
            onReviewAlternatives()
        } label: {
            Text("Review alternatives")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(reviewButtonBackground)
                .foregroundColor(.black)
                .overlay(reviewButtonBorder)
        }
        .buttonStyle(.plain)
    }

    private var reviewButtonBackground: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)
            Capsule()
                .fill(Color.yellow.opacity(0.75))
        }
    }

    private var reviewButtonBorder: some View {
        Capsule()
            .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
            .blendMode(.overlay)
    }

    private var dismissButton: some View {
        Button {
            feedback.lightImpact()
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
                .circularMaterialControl(size: 32)
        }
        .buttonStyle(.plain)
        .offset(x: 4, y: -4)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(colorScheme == .dark ? Color.black.opacity(0.5) : Color(uiColor: .systemBackground))
            .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .stroke(Color(UIColor.separator), lineWidth: 0.5)
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
        onDismiss: {},
        imageDependencies: CandidateReviewDependencies().imageDependencies,
        feedback: .init()
    )
    .padding()
}
#endif
