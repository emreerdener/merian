import SwiftUI

struct ExplorePostActionSkeleton: View {
    let fill: Color
    let secondaryFill: Color
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .title3) private var rowHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var chipHeight: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var countHeight: CGFloat = 17

    private var usesSecondRow: Bool { dynamicType.isAccessibilitySize || dynamicType == .xxxLarge }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                countedAction
                countedAction
                actionIcon
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(fill)
                            .frame(width: 9, height: 9)
                            .offset(x: 4, y: 2)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                if !usesSecondRow { reactionStrip } else { Spacer(minLength: 0) }
                actionIcon
                    .frame(minWidth: 44, minHeight: 44)
            }
            if usesSecondRow { reactionStrip }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var countedAction: some View {
        HStack(spacing: 4) {
            actionIcon
            if !dynamicType.isAccessibilitySize {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(fill)
                    .frame(width: countHeight * 0.65, height: countHeight)
            }
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    private var actionIcon: some View {
        Circle()
            .fill(secondaryFill)
            .frame(width: 20, height: 20)
    }

    private var reactionStrip: some View {
        GeometryReader { _ in
            HStack(spacing: 6) {
                ForEach(0..<4) { _ in
                    Capsule()
                        .fill(secondaryFill)
                        .frame(width: chipHeight * 1.6, height: chipHeight)
                }
            }
            .frame(height: rowHeight)
        }
        .frame(height: rowHeight)
        .clipped()
        .mask {
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 24)
            }
        }
    }
}
