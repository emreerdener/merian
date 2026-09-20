import SwiftUI

struct ExplorePostActionSkeleton: View {
    let fill: Color

    var body: some View {
        HStack(spacing: 8) {
            actionNode
            actionNode
            actionNode
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var actionNode: some View {
        Circle()
            .fill(fill)
            .frame(width: 20, height: 20)
            .frame(width: 44, height: 44)
    }
}
