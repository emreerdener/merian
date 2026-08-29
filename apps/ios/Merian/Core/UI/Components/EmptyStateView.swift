import SwiftUI

/// Cross-feature empty-state composition with optional artwork and action
/// content. Product areas retain ownership of visible copy and behavior.
public struct EmptyStateView<Content: View>: View {
    let iconName: String?
    let imageName: String?
    let imageHeight: CGFloat
    let title: String
    let message: String
    let content: Content

    public init(
        iconName: String? = nil,
        imageName: String? = nil,
        title: String,
        message: String,
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) {
        self.init(
            iconName: iconName,
            imageName: imageName,
            imageHeight: 200,
            title: title,
            message: message,
            content: content
        )
    }

    public init(
        iconName: String? = nil,
        imageName: String? = nil,
        imageHeight: CGFloat,
        title: String,
        message: String,
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) {
        self.iconName = iconName
        self.imageName = imageName
        self.imageHeight = imageHeight
        self.title = title
        self.message = message
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if let imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(height: imageHeight)
                    .padding(.bottom, 16)
            } else if let iconName {
                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            content

            Spacer()
        }
        .padding()
    }
}
