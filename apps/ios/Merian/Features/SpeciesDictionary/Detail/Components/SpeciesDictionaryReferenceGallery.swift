import SwiftUI

enum SpeciesDictionaryHeroLayout {
    static let contentOverlap: CGFloat = 32
    static let overlayInset: CGFloat = 14
    static let overlayBottomInset = contentOverlap + overlayInset
}

struct SpeciesDictionaryReferenceGallery: View {
    let scientificName: String
    let images: [SpeciesDictionaryReferenceImage]
    let onImageLoadFailed: ((SpeciesDictionaryReferenceImage) -> Void)?
    let onHeroBottomChange: ((CGFloat) -> Void)?
    let onImageTap: ((InsightImageGalleryPresentation) -> Void)?
    let onAuthorTap: ((SpeciesDictionaryReferenceImage) -> Void)?

    @State private var selectedImageId: String?
    @State private var failedImageIds = Set<String>()

    init(
        scientificName: String,
        images: [SpeciesDictionaryReferenceImage],
        onImageLoadFailed: ((SpeciesDictionaryReferenceImage) -> Void)? = nil,
        onHeroBottomChange: ((CGFloat) -> Void)? = nil,
        onImageTap: ((InsightImageGalleryPresentation) -> Void)? = nil,
        onAuthorTap: ((SpeciesDictionaryReferenceImage) -> Void)? = nil
    ) {
        self.scientificName = scientificName
        self.images = SpeciesDictionaryImageGalleryBuilder.allowedImages(from: images)
        self.onImageLoadFailed = onImageLoadFailed
        self.onHeroBottomChange = onHeroBottomChange
        self.onImageTap = onImageTap
        self.onAuthorTap = onAuthorTap
    }

    private let imageSize: CGFloat = UIScreen.main.bounds.width
    private let bleedBuffer: CGFloat = 50

    private var currentImageId: String? {
        selectedImageId ?? images.first?.id
    }

    var body: some View {
        GeometryReader { proxy in
            let heroFrame = proxy.frame(in: .named("SpeciesDictionaryScrollSpace"))
            let scrollY = heroFrame.minY

            carousel
                .frame(
                    width: imageSize,
                    height: scrollY > 0 ? imageSize + scrollY + bleedBuffer : imageSize + bleedBuffer
                )
                .overlay(alignment: .bottom) { paginationDots }
                .offset(y: scrollY > 0 ? -(scrollY + bleedBuffer) : -bleedBuffer)
                .ignoresSafeArea(.all, edges: .top)
                .onChange(of: heroFrame.maxY, initial: true) { _, newMaxY in
                    onHeroBottomChange?(newMaxY)
                }
        }
        .frame(height: imageSize)
        .ignoresSafeArea(.all, edges: .top)
        .zIndex(0)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var paginationDots: some View {
        if images.count > 1 {
            HStack(spacing: 8) {
                ForEach(images) { image in
                    Circle()
                        .fill(image.id == currentImageId ? Color.white : Color.white.opacity(0.4))
                        .frame(width: 6, height: 6)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.2))
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, SpeciesDictionaryHeroLayout.overlayBottomInset)
            .allowsHitTesting(false)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedImageId)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity
            ))
        }
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
        ZStack(alignment: .bottom) {
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
            .contentShape(Rectangle())
            .onTapGesture {
                presentFullscreenGallery(startingAt: image.id)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(accessibilityLabel(for: image))

            HStack(spacing: 8) {
                authorBadge(for: image)

                Spacer(minLength: 44)

                sourceBadge(for: image)
            }
            .padding(.horizontal, SpeciesDictionaryHeroLayout.overlayInset)
            .padding(.top, SpeciesDictionaryHeroLayout.overlayInset)
            .padding(.bottom, SpeciesDictionaryHeroLayout.overlayBottomInset)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func authorBadge(for image: SpeciesDictionaryReferenceImage) -> some View {
        if let username = image.naturebookAuthorUsername {
            if let onAuthorTap,
               let authorUserId = image.authorUserId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !authorUserId.isEmpty {
                Button {
                    onAuthorTap(image)
                } label: {
                    authorBadgeLabel(username: username)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open @\(username)’s profile")
            } else {
                authorBadgeLabel(username: username)
                    .accessibilityLabel("Photo by @\(username)")
            }
        }
    }

    private func authorBadgeLabel(username: String) -> some View {
        Text("@\(username)")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .frame(maxWidth: 132, alignment: .leading)
    }

    private func sourceBadge(for image: SpeciesDictionaryReferenceImage) -> some View {
        Text(image.source.label)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .accessibilityHidden(true)
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
        return "\(image.source.label) reference image for \(scientificName)"
    }

    private func trackLoadFailure(for image: SpeciesDictionaryReferenceImage) {
        guard !failedImageIds.contains(image.id) else { return }
        failedImageIds.insert(image.id)
        onImageLoadFailed?(image)
    }

    private func presentFullscreenGallery(startingAt imageID: String?) {
        guard let presentation = SpeciesDictionaryImageGalleryBuilder.presentation(
            for: images,
            selectedImageID: imageID
        ) else { return }

        onImageTap?(presentation)
    }
}

struct SpeciesDictionaryImageGalleryBuilder {
    static func allowedImages(
        from images: [SpeciesDictionaryReferenceImage]
    ) -> [SpeciesDictionaryReferenceImage] {
        images.filter { ExternalReferenceImagePolicy.isAllowed($0.url) }
    }

    static func buildItems(for images: [SpeciesDictionaryReferenceImage]) -> [InsightImageGalleryItem] {
        allowedImages(from: images).map { image in
            InsightImageGalleryItem(
                id: "species-reference-\(image.id)",
                source: .referenceURL(image.url),
                referenceAttributionLabel: image.fullscreenAttributionLabel
            )
        }
    }

    static func presentation(
        for images: [SpeciesDictionaryReferenceImage],
        selectedImageID: String?
    ) -> InsightImageGalleryPresentation? {
        let allowedImages = allowedImages(from: images)
        let items = buildItems(for: allowedImages)
        guard !items.isEmpty else { return nil }

        let selectedIndex = allowedImages.firstIndex { image in
            image.id == selectedImageID
        } ?? 0

        return InsightImageGalleryPresentation(
            items: items,
            initialSelectedIndex: selectedIndex
        )
    }
}
