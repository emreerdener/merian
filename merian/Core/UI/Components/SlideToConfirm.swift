import SwiftUI

// MARK: - Slide To Confirm

/// A pill-shaped drag-to-confirm control that mirrors the classic iPhone unlock gesture.
///
/// The user drags the thumb from the left edge to the right. When it reaches ≥88% of the
/// track, `onConfirm` fires automatically with a success haptic. Releasing before the
/// threshold springs the thumb back to the start. Once fired the control is disabled to
/// prevent double-triggers.
///
/// Usage — drop in as a direct replacement for a green confirm `Button`:
/// ```swift
/// SlideToConfirm(label: confirmButtonTitle, onConfirm: onConfirm)
/// ```
struct SlideToConfirm: View {
    let label: String
    let onConfirm: () -> Void
    var color: Color = .green

    @State private var dragOffset: CGFloat = 0
    @State private var isCompleted = false
    @State private var hasPlayedEdgeHaptic = false

    private let thumbSize: CGFloat = 44
    private let trackHeight: CGFloat = 56
    private let thumbInset: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let maxOffset = geo.size.width - thumbSize - thumbInset * 2
            let progress: CGFloat = maxOffset > 0 ? min(1, dragOffset / maxOffset) : 0

            ZStack(alignment: .leading) {
                // Base track fill
                Capsule()
                    .fill(color.opacity(0.12))

                // Progressive fill that expands behind the thumb
                Capsule()
                    .fill(color.opacity(progress * 0.18))

                // Label — centered over the full track width; thumb sits on top via ZStack.
                Text(label)
                    .font(.headline)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .opacity(max(0, 1.0 - progress * 2.5))
                    .frame(maxWidth: .infinity, alignment: .center)

                // Thumb
                Circle()
                    .fill(isCompleted ? color : color.opacity(0.9))
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        ZStack {
                            if isCompleted {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                // Chevrons suggest rightward motion
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
                    )
                    .padding(.leading, thumbInset)
                    .offset(x: dragOffset)
                    .shadow(color: color.opacity(0.25 + progress * 0.25), radius: 8, x: 0, y: 4)
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                guard !isCompleted else { return }
                                dragOffset = min(max(0, value.translation.width), maxOffset)
                                if dragOffset >= maxOffset {
                                    if !hasPlayedEdgeHaptic {
                                        HapticManager.shared.triggerLightImpact()
                                        hasPlayedEdgeHaptic = true
                                    }
                                } else {
                                    hasPlayedEdgeHaptic = false
                                }
                            }
                            .onEnded { _ in
                                guard !isCompleted else { return }
                                if progress >= 0.88 {
                                    fire(maxOffset: maxOffset)
                                } else {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                                        dragOffset = 0
                                    }
                                    HapticManager.shared.triggerLightImpact()
                                }
                            }
                    )
                    .animation(.interactiveSpring(), value: dragOffset)
            }
        }
        .frame(height: trackHeight)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func fire(maxOffset: CGFloat) {
        HapticManager.shared.triggerSuccessPulse()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            dragOffset = maxOffset
            isCompleted = true
        }
        // Brief pause so the user sees the completed state before the view transitions.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            onConfirm()
        }
    }
}

#if DEBUG
#Preview("Idle") {
    SlideToConfirm(label: "Confirm Monarch Butterfly", onConfirm: {})
        .padding(.horizontal, 24)
}

#Preview("Dark") {
    SlideToConfirm(label: "Confirm Danaus plexippus", onConfirm: {})
        .padding(.horizontal, 24)
        .preferredColorScheme(.dark)
}
#endif
