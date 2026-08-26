import SwiftUI

struct FieldTripRemoteImage: View {
    let urlString: String?
    let placeholderSystemImage: String
    let placeholderFontSize: CGFloat

    init(
        urlString: String?,
        placeholderSystemImage: String = "leaf",
        placeholderFontSize: CGFloat = 28
    ) {
        self.urlString = urlString
        self.placeholderSystemImage = placeholderSystemImage
        self.placeholderFontSize = placeholderFontSize
    }

    var body: some View {
        if let url = SecureTransportPolicy.httpsURL(from: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    placeholder
                        .redacted(reason: .placeholder)
                @unknown default:
                    placeholder
                }
            }
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemGroupedBackground)
            Image(systemName: placeholderSystemImage)
                .font(.system(size: placeholderFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
