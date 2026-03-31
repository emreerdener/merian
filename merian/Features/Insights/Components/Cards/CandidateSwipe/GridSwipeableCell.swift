import SwiftUI

// MARK: - Swipe Direction
enum CandidateSwipeDirection {
    case left
    case right
}

// MARK: - Grid Swipeable Cell
struct GridSwipeableCell: View {
    let candidate: IdentificationCandidate
    let onConfirm: () -> Void
    let onReject: () -> Void

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
            isSwipingLeft: isSwipingLeft
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: offset.width, y: 0)
        .rotationEffect(.degrees(Double(offset.width) / 25.0))
        .gesture(
            DragGesture()
                .onChanged { value in
                    offset = value.translation
                    isDragging = true
                }
                .onEnded { value in
                    if abs(value.translation.width) >= swipeThreshold {
                        animateSwipe(direction: value.translation.width > 0 ? .right : .left)
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                            offset = .zero
                            isDragging = false
                        }
                    }
                }
        )
    }

    private func animateSwipe(direction: CandidateSwipeDirection) {
        let targetX: CGFloat = direction == .right ? 700 : -700
        withAnimation(.easeInOut(duration: 0.3)) {
            offset = CGSize(width: targetX, height: 60)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            switch direction {
            case .right: onConfirm()
            case .left: onReject()
            }
        }
    }
}
