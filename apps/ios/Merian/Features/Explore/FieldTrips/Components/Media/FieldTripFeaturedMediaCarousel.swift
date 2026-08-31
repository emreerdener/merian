import SwiftUI

struct FieldTripFeaturedMediaCarousel: View {
    let items: [FieldTripFeaturedMediaItem]
    let onMediaLoadFailed: (String) -> Void
    let onOpenViewer: (String) -> Void

    @State private var selectedIndex = 0
    @State private var selectedItemId: String?

    private var carouselPages: [NativePageCarouselPage] {
        items.map { item in
            NativePageCarouselPage(
                id: item.id,
                reuseKey: AnyHashable(item.pageReuseIdentity),
                view: AnyView(page(for: item))
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let heroFrame = proxy.frame(
                in: .named(FieldTripFeaturedMediaLayout.scrollCoordinateSpace)
            )
            let scrollOffset = heroFrame.minY

            NativePageCarousel(selectedIndex: $selectedIndex, pages: carouselPages)
                .frame(
                    width: proxy.size.width,
                    height: FieldTripFeaturedMediaLayout.heroHeight(
                        baseHeight: proxy.size.height,
                        scrollOffset: scrollOffset
                    )
                )
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipped()
                .overlay(alignment: .bottom) {
                    MediaCarouselPaginationDots(
                        pageCount: items.count,
                        selectedIndex: selectedIndex,
                        bottomPadding: FieldTripFeaturedMediaLayout.overlayBottomInset,
                        accessibilityNoun: "Featured image"
                    )
                }
                .overlay { referenceAttributionTags }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { _ in
                        openSelectedPage()
                    }
                )
                .offset(
                    y: FieldTripFeaturedMediaLayout.heroOffset(scrollOffset: scrollOffset)
                )
                .ignoresSafeArea(.all, edges: .top)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .ignoresSafeArea(.all, edges: .top)
        .onAppear(perform: reconcileSelection)
        .onChange(of: selectedIndex) { _, newValue in
            guard let item = items[safe: newValue] else { return }
            selectedItemId = item.id
        }
        .onChange(of: items.map(\.id)) { _, _ in
            reconcileSelection()
        }
        .accessibilityIdentifier("FieldTripFeaturedMediaCarousel")
    }

    private func page(for item: FieldTripFeaturedMediaItem) -> some View {
        ZStack {
            AsyncLocalImageView(
                path: item.source.localPath,
                fallbackImageUrl: item.source.fallbackImageURL,
                contentMode: .fill,
                unavailableContext: .originalPhoto,
                onImageLoadFailed: {
                    onMediaLoadFailed(item.source.posterPath)
                }
            )

            if item.source.isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.black.opacity(0.45), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
                    .accessibilityHidden(true)
            }

        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityHint("Opens the full-screen media viewer")
        .accessibilityIdentifier("FieldTripFeaturedMediaPage_\(item.id)")
        .accessibilityAction {
            onOpenViewer(item.id)
        }
    }

    @ViewBuilder
    private var referenceAttributionTags: some View {
        if let item = items[safe: selectedIndex] {
            ZStack {
                if let contributorLabel = item.source.inlineContributorAttributionLabel {
                    referenceAttributionTag(contributorLabel)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottomLeading
                        )
                }

                if let sourceLabel = item.source.inlineAttributionLabel {
                    referenceAttributionTag(sourceLabel)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottomTrailing
                        )
                }
            }
            .padding(.horizontal, FieldTripFeaturedMediaLayout.overlayInset)
            .padding(.bottom, FieldTripFeaturedMediaLayout.overlayBottomInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .animation(
                .spring(response: 0.3, dampingFraction: 0.8),
                value: selectedItemId
            )
        }
    }

    private func referenceAttributionTag(_ label: String) -> some View {
        Text(label)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.28))
            }
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }

    private func openSelectedPage() {
        guard let item = items[safe: selectedIndex] else { return }
        onOpenViewer(item.id)
    }

    private func reconcileSelection() {
        let nextIndex = FieldTripFeaturedMediaPresentation.selectedIndex(
            preserving: selectedItemId,
            previousSelectedIndex: selectedIndex,
            in: items
        )
        selectedIndex = nextIndex
        selectedItemId = items[safe: nextIndex]?.id
    }
}
