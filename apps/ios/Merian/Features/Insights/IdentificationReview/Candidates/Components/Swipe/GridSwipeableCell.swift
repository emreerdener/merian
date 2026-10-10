import SwiftUI

// MARK: - Grid Swipeable Cell
struct GridSwipeableCell: View {
    let candidate: IdentificationCandidate
    let imageDependencies: SimilarSpeciesImageDependencies
    let feedback: IdentificationReviewFeedbackDependencies
    let onConfirm: () -> Void
    let onReject: () -> Void
    var protectedReview: AnalysisCandidateReviewModel?
    var onImmediateConfirm: (() -> Void)?

    @State private var offset: CGSize = .zero
    @State private var isDragging = false
    private let swipeThreshold: CGFloat = 240
    
    private var dragPercentage: Double { min(abs(offset.width) / swipeThreshold, 1.0) }
    private var isSwipingRight: Bool { isDragging && offset.width > 10 }
    private var isSwipingLeft: Bool { isDragging && offset.width < -10 }
    
    var body: some View {
        SwipeableCandidateCard(
            candidate: candidate,
            isDragging: isDragging,
            dragPercentage: dragPercentage,
            isSwipingRight: isSwipingRight,
            isSwipingLeft: isSwipingLeft,
            imageDependencies: imageDependencies,
            feedback: feedback, protectedReview: protectedReview
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: offset.width, y: 0)
        .rotationEffect(.degrees(Double(offset.width) / 25.0))
        .gesture(candidateDrag, isEnabled: protectedReview == nil)
        .simultaneousGesture(candidateDrag, isEnabled: protectedReview != nil)
    }

    // Protected cards live in a vertical history sheet. Their horizontal review
    // gesture must not prevent scrolling to another saved alternative.
    private var candidateDrag: some Gesture {
        DragGesture(minimumDistance: protectedReview == nil ? 10 : 30)
            .onChanged { value in
                guard protectedReview == nil || abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = value.translation
                isDragging = true
            }
            .onEnded { value in
                let horizontal = protectedReview == nil || abs(value.translation.width) > abs(value.translation.height)
                if horizontal && abs(value.translation.width) >= swipeThreshold {
                    feedback.mediumPulse()
                    animateSwipe(direction: value.translation.width > 0 ? .right : .left)
                } else {
                    feedback.lightImpact()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                        offset = .zero
                        isDragging = false
                    }
                }
            }
    }

    private func animateSwipe(direction: CandidateSwipeDirection) {
        if direction == .right, let onImmediateConfirm {
            // Protected admission happens at gesture end, before animation or dismissal.
            offset = .zero; isDragging = false; onImmediateConfirm(); return
        }
        let targetX: CGFloat = direction == .right ? 700 : -700
        withAnimation(.easeInOut(duration: 0.3)) {
            offset = CGSize(width: targetX, height: 60)
        } completion: {
            switch direction {
            case .right: onConfirm()
            case .left: onReject()
            }
        }
    }
}
