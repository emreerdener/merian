import SwiftUI

struct SpeciesDictionaryReferenceGallery: View {
    let scientificName: String
    let images: [SpeciesDictionaryReferenceImage]
    let onImageLoadFailed: ((SpeciesDictionaryReferenceImage) -> Void)?

    @State private var selectedImageId: String?
    @State private var failedImageIds = Set<String>()

    init(
        scientificName: String,
        images: [SpeciesDictionaryReferenceImage],
        onImageLoadFailed: ((SpeciesDictionaryReferenceImage) -> Void)? = nil
    ) {
        self.scientificName = scientificName
        self.images = images
        self.onImageLoadFailed = onImageLoadFailed
    }

    private let imageSize: CGFloat = UIScreen.main.bounds.width
    private let bleedBuffer: CGFloat = 50

    private var currentImageId: String? {
        selectedImageId ?? images.first?.id
    }

    private var currentImage: SpeciesDictionaryReferenceImage? {
        images.first { $0.id == currentImageId } ?? images.first
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                let scrollY = proxy.frame(in: .named("SpeciesDictionaryScrollSpace")).minY

                carousel
                    .frame(
                        width: imageSize,
                        height: scrollY > 0 ? imageSize + scrollY + bleedBuffer : imageSize + bleedBuffer
                    )
                    .offset(y: scrollY > 0 ? -(scrollY + bleedBuffer) : -bleedBuffer)
                    .ignoresSafeArea(.all, edges: .top)
            }
            .frame(height: imageSize)
            .ignoresSafeArea(.all, edges: .top)
            .zIndex(0)

            if images.count > 1 {
                HStack(spacing: 8) {
                    ForEach(images) { image in
                        Circle()
                            .fill(image.id == currentImageId ? Color.primary : Color.primary.opacity(0.18))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
            }

            if let attributionCaption = currentImage?.attributionCaption {
                Text(attributionCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .accessibilityLabel("Reference image attribution: \(attributionCaption)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var carousel: some View {
        if images.isEmpty {
            placeholder
        } else {
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(images) { image in
                            page(for: image)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .id(image.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: Binding(
                    get: { currentImageId },
                    set: { selectedImageId = $0 }
                ))
                .background(Color(uiColor: .secondarySystemBackground))
                .clipped()
                .onAppear {
                    if selectedImageId == nil {
                        selectedImageId = images.first?.id
                    }
                }
            }
        }
    }

    private func page(for image: SpeciesDictionaryReferenceImage) -> some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { proxy in
                AsyncLocalImageView(
                    path: nil,
                    fallbackImageUrl: image.url,
                    fillHeight: true,
                    onImageLoadFailed: {
                        trackLoadFailure(for: image)
                    }
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(Color(uiColor: .secondarySystemBackground))
            }

            Text(image.source.label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule(style: .continuous))
                .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: image))
    }

    private var placeholder: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            Image(systemName: "leaf.circle")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
    }

    private func accessibilityLabel(for image: SpeciesDictionaryReferenceImage) -> String {
        if let attributionCaption = image.attributionCaption {
            return "\(image.source.label) reference image for \(scientificName), \(attributionCaption)"
        }
        return "\(image.source.label) reference image for \(scientificName)"
    }

    private func trackLoadFailure(for image: SpeciesDictionaryReferenceImage) {
        guard !failedImageIds.contains(image.id) else { return }
        failedImageIds.insert(image.id)
        onImageLoadFailed?(image)
    }
}
