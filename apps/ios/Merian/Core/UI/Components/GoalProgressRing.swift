import SwiftUI

struct GoalProgressRing: View {
    let completedCount: Int
    let targetCount: Int

    private var fractionComplete: CGFloat {
        guard targetCount > 0 else { return 0 }
        return min(
            max(CGFloat(completedCount) / CGFloat(targetCount), 0),
            1
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.28), lineWidth: 3.5)

            Circle()
                .trim(from: 0, to: fractionComplete)
                .stroke(
                    .primary,
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(completedCount)/\(targetCount)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(5)
        }
        .padding(2)
    }
}
