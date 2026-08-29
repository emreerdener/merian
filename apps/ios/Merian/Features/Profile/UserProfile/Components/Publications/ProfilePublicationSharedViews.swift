import SwiftUI

struct ProfileAuthorAvatar: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    fallback
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                @unknown default:
                    fallback
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            fallback
        }
    }

    private var fallback: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}

extension View {
    func profileExploreStateStyle() -> some View {
        font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }
}
