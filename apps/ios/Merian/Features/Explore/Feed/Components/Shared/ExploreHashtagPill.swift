import SwiftUI

struct ExploreHashtagPill: View {
    let hashtag: String

    var body: some View {
        Text("#\(hashtag)")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
            )
    }
}
