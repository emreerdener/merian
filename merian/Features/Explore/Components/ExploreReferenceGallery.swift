import SwiftUI

struct ExploreReferenceGallery: View {
    let scientificName: String
    let images: [ExploreReferenceGalleryImage]
    @State private var selectedImageId: String?
    @State private var failedImageIds: Set<String> = []

    private var activeImages: [ExploreReferenceGalleryImage] {
        let valid = images.filter { !failedImageIds.contains($0.id) }
        let failed = images.filter { failedImageIds.contains($0.id) }
        return valid + failed
    }

    private var carouselHeight: CGFloat {
        min(UIScreen.main.bounds.width * 0.96, 420)
    }

    private var currentImageId: String? {
        selectedImageId ?? activeImages.first?.id
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(activeImages) { image in
                        ExploreReferenceGalleryPage(
                            scientificName: scientificName,
                            image: image,
                            height: carouselHeight,
                            onLoadFailed: {
                                Task { @MainActor in
                                    if !failedImageIds.contains(image.id) {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            failedImageIds.insert(image.id)
                                            if selectedImageId == image.id {
                                                selectedImageId = activeImages.first?.id
                                            }
                                        }
                                    }
                                }
                            }
                        )
                        .frame(height: carouselHeight)
                        .containerRelativeFrame(.horizontal)
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
            .frame(height: carouselHeight)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipped()

            if activeImages.count > 1 {
                HStack(spacing: 8) {
                    ForEach(activeImages) { image in
                        Circle()
                            .fill(image.id == currentImageId ? Color.primary : Color.primary.opacity(0.18))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, -16)
        .onAppear {
            if selectedImageId == nil {
                selectedImageId = activeImages.first?.id
            }
        }
    }
}

private struct ExploreReferenceGalleryPage: View {
    let scientificName: String
    let image: ExploreReferenceGalleryImage
    let height: CGFloat
    var onLoadFailed: (() -> Void)?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { proxy in
                AsyncLocalImageView(
                    path: nil,
                    fallbackImageUrl: image.url,
                    fillHeight: true,
                    onImageLoadFailed: onLoadFailed
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
        .frame(height: height)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(image.source.label) reference image for \(scientificName)")
    }
}
