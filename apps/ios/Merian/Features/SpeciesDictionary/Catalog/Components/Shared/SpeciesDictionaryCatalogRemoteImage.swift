import SwiftUI

struct SpeciesDictionaryCatalogRemoteImage: View {
    let source: String?
    var prominentPlaceholder = false
    var dependencies: SpeciesCatalogImageDependencies = .live

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: sanitizedSource) {
            image = nil
            guard let sanitizedSource else { return }
            let loadedImage = await dependencies.loadImage(
                sanitizedSource,
                Int(MerianConfig.displayImageMaxSize)
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
        }
    }

    private var sanitizedSource: String? {
        ExternalReferenceImagePolicy.url(from: source)?.absoluteString
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            .overlay {
                if prominentPlaceholder {
                    Image(systemName: "leaf")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "leaf")
                        .foregroundStyle(.secondary)
                }
            }
    }
}
