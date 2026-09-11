import SwiftUI

/// A pill-shaped drag-to-confirm control for identification-review actions.
struct SlideToConfirm: View {
    let label: String
    let onConfirm: () -> Void
    let feedback: IdentificationReviewFeedbackDependencies
    var color: Color = .green

    @State private var dragOffset: CGFloat = 0
    @State private var isCompleted = false
    @State private var hasPlayedEdgeHaptic = false

    private let thumbSize: CGFloat = 44
    private let trackHeight: CGFloat = 56
    private let thumbInset: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let maxOffset = geometry.size.width
                - thumbSize
                - thumbInset * 2
            let progress: CGFloat = maxOffset > 0
                ? min(1, dragOffset / maxOffset)
                : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.12))

                Capsule()
                    .fill(color.opacity(progress * 0.18))

                Text(label)
                    .font(.headline)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .opacity(max(0, 1 - progress * 2.5))
                    .padding(.horizontal, thumbSize + thumbInset * 2)
                    .frame(maxWidth: .infinity, alignment: .center)

                thumb(maxOffset: maxOffset, progress: progress)
            }
        }
        .frame(height: trackHeight)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
        )
        .task(id: isCompleted) {
            guard isCompleted else { return }
            do {
                try await Task.sleep(for: .milliseconds(380))
            } catch {
                return
            }
            guard !Task.isCancelled, isCompleted else { return }
            onConfirm()
        }
    }

    private func thumb(maxOffset: CGFloat, progress: CGFloat) -> some View {
        Circle()
            .fill(isCompleted ? color : color.opacity(0.9))
            .frame(width: thumbSize, height: thumbSize)
            .overlay(thumbSymbol(progress: progress))
            .padding(.leading, thumbInset)
            .offset(x: dragOffset)
            .shadow(
                color: color.opacity(0.25 + progress * 0.25),
                radius: 8,
                x: 0,
                y: 4
            )
            .gesture(dragGesture(maxOffset: maxOffset, progress: progress))
            .animation(.interactiveSpring(), value: dragOffset)
    }

    @ViewBuilder
    private func thumbSymbol(progress: CGFloat) -> some View {
        if isCompleted {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .transition(.scale.combined(with: .opacity))
        } else {
            HStack(spacing: -8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white.opacity(0.5 + progress * 0.5))
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white.opacity(0.25 + progress * 0.75))
            }
        }
    }

    private func dragGesture(
        maxOffset: CGFloat,
        progress: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !isCompleted else { return }
                dragOffset = min(
                    max(0, value.translation.width),
                    maxOffset
                )
                if dragOffset >= maxOffset {
                    if !hasPlayedEdgeHaptic {
                        feedback.lightImpact()
                        hasPlayedEdgeHaptic = true
                    }
                } else {
                    hasPlayedEdgeHaptic = false
                }
            }
            .onEnded { _ in
                completeDrag(
                    progress: progress,
                    maxOffset: maxOffset
                )
            }
    }

    private func completeDrag(
        progress: CGFloat,
        maxOffset: CGFloat
    ) {
        guard !isCompleted else { return }
        if progress >= 0.88 {
            fire(maxOffset: maxOffset)
        } else {
            withAnimation(.spring(
                response: 0.45,
                dampingFraction: 0.72
            )) {
                dragOffset = 0
            }
            feedback.lightImpact()
        }
    }

    private func fire(maxOffset: CGFloat) {
        feedback.successPulse()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            dragOffset = maxOffset
            isCompleted = true
        }
    }
}

#if DEBUG
#Preview("Idle") {
    SlideToConfirm(
        label: "Confirm Monarch Butterfly",
        onConfirm: {},
        feedback: .init()
    )
    .padding(.horizontal, 24)
}

#Preview("Dark") {
    SlideToConfirm(
        label: "Confirm Danaus plexippus",
        onConfirm: {},
        feedback: .init()
    )
    .padding(.horizontal, 24)
    .preferredColorScheme(.dark)
}
#endif
