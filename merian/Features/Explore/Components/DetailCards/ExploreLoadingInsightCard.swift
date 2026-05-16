import SwiftUI

struct ExploreLoadingInsightCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlowPulsingSkeletonView(cornerRadius: 8)
                .frame(width: 180, height: 16)

            GlowPulsingSkeletonView(cornerRadius: 6)
                .frame(height: 10)

            GlowPulsingSkeletonView(cornerRadius: 6)
                .frame(maxWidth: 240)
                .frame(height: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityLabel("Loading species details")
    }
}
