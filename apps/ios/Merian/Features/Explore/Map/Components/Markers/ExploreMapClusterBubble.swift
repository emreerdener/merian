import SwiftUI

struct ExploreMapClusterBubble: View {
    let postCount: Int

    var body: some View {
        Text(postCount.formatted(.number.notation(.compactName)))
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.96))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.5), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
    }
}
