import SwiftUI

// MARK: - Swipe Indicator
struct CandidateSwipeIndicator: View {
    let label: String
    let iconName: String
    let color: Color
    let progress: Double
    let feedback: IdentificationReviewFeedbackDependencies

    // Delays the indicator progression until the user reaches 20% of the drag threshold
    private var adjustedProgress: Double {
        max(0, (progress - 0.2) / 0.8)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.25), lineWidth: 3.5)
                        .frame(width: 48, height: 48)

                    Circle()
                        .trim(from: 0, to: CGFloat(adjustedProgress))
                        .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.05), value: adjustedProgress)
                }
                .opacity(adjustedProgress >= 1.0 ? 0 : 1)

                Circle()
                    .fill(.white)
                    .frame(width: 48, height: 48)
                    .scaleEffect(adjustedProgress >= 1.0 ? 1.0 : 0.001)
                    .opacity(adjustedProgress >= 1.0 ? 1.0 : 0.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: adjustedProgress >= 1.0)

                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(adjustedProgress >= 1.0 ? color : .white)
                    .scaleEffect(0.6 + (adjustedProgress * 0.4))
            }

            Text(label)
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .opacity(min(adjustedProgress * 2, 1))
        }
        .onChange(of: adjustedProgress >= 1.0) { _, isFullyActivated in
            if isFullyActivated {
                feedback.selection()
            }
        }
    }
}
