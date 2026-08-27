import SwiftUI

struct ExploreAuthorAvatar: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
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
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}
