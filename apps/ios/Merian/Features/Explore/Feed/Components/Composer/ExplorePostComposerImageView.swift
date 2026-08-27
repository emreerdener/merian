import SwiftUI

struct ExplorePostComposerImageView: View {
    enum Placeholder {
        case discovery
        case media(ExplorePostComposerMediaKind)

        var systemImage: String {
            switch self {
            case .discovery:
                "leaf"
            case .media(.audio):
                "waveform"
            case .media(.video):
                "play.rectangle.fill"
            case .media(.image):
                "photo"
            }
        }
    }

    let path: String?
    let maxDimension: Int
    let placeholder: Placeholder
    private let dependencies: ExplorePostComposerImageDependencies

    @State private var image: UIImage?

    init(
        path: String?,
        maxDimension: Int,
        placeholder: Placeholder,
        dependencies: ExplorePostComposerImageDependencies = .live
    ) {
        self.path = path
        self.maxDimension = maxDimension
        self.placeholder = placeholder
        self.dependencies = dependencies
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(uiColor: .tertiarySystemFill)
                    .overlay {
                        placeholderImage
                    }
            }
        }
        .task(id: path) {
            image = nil
            guard let path, !path.isEmpty else { return }
            image = await dependencies.loadImage(path, maxDimension)
        }
    }

    @ViewBuilder
    private var placeholderImage: some View {
        switch placeholder {
        case .discovery:
            Image(systemName: placeholder.systemImage)
                .foregroundStyle(.secondary)
        case .media:
            Image(systemName: placeholder.systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
