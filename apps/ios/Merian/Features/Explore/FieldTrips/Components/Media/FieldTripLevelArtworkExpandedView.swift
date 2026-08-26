import SwiftUI

struct FieldTripLevelArtworkExpandedView: View {
    let items: [FieldTripLevelArtworkGalleryItem]
    let initialItemID: String
    let onOpenFieldTrip: ((FieldTripLevelArtworkGalleryItem) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedItemID: String?

    init(
        items: [FieldTripLevelArtworkGalleryItem],
        initialItemID: String,
        onOpenFieldTrip: ((FieldTripLevelArtworkGalleryItem) -> Void)? = nil
    ) {
        self.items = items
        self.initialItemID = initialItemID
        self.onOpenFieldTrip = onOpenFieldTrip
        _selectedItemID = State(initialValue: initialItemID)
    }

    private var selectedItem: FieldTripLevelArtworkGalleryItem? {
        items.first(where: { $0.id == selectedItemID })
            ?? items.first(where: { $0.id == initialItemID })
            ?? items.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(items) { item in
                            ZoomableScrollView(onSwipeDown: { dismiss() }) {
                                Image(item.imageName)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(24)
                                    .accessibilityLabel("\(item.title) patch")
                            }
                            .containerRelativeFrame(.horizontal)
                            .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $selectedItemID)
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 10) {
                        if let selectedItem {
                            Text(selectedItem.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }

                        if items.count > 1 {
                            HStack(spacing: 8) {
                                ForEach(items) { item in
                                    Circle()
                                        .fill(
                                            item.id == selectedItem?.id
                                                ? Color.white
                                                : Color.white.opacity(0.35)
                                        )
                                        .frame(width: 7, height: 7)
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Patch \(selectedPageNumber) of \(items.count)")
                        }

                        Text(viewerHint)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { viewerToolbar }
            .onAppear {
                if !items.contains(where: { $0.id == selectedItemID }) {
                    selectedItemID = items.first?.id
                }
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }

    @ToolbarContentBuilder
    private var viewerToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .imageOverlayToolbarIconChrome(
                        isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground
                    )
            }
            .imageOverlayToolbarButtonChrome(
                isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground
            )
            .accessibilityLabel("Close patch viewer")
            .accessibilityIdentifier("FieldTripPatchViewerClose")
        }

        if onOpenFieldTrip != nil, selectedItem != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: openSelectedFieldTrip) {
                        Label("View field trip", systemImage: "binoculars")
                    }
                    .accessibilityIdentifier("FieldTripPatchViewerOpenFieldTrip")
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .imageOverlayToolbarIconChrome(
                            isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground
                        )
                }
                .imageOverlayToolbarButtonChrome(
                    isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground
                )
                .accessibilityLabel("Patch options")
                .accessibilityIdentifier("FieldTripPatchViewerOptions")
            }
        }
    }

    private func openSelectedFieldTrip() {
        guard let selectedItem, let onOpenFieldTrip else { return }
        HapticManager.shared.triggerSelectionPulse()
        onOpenFieldTrip(selectedItem)
        dismiss()
    }

    private var selectedPageNumber: Int {
        guard let selectedItem,
              let index = items.firstIndex(where: { $0.id == selectedItem.id }) else {
            return items.isEmpty ? 0 : 1
        }
        return index + 1
    }

    private var viewerHint: String {
        if items.count > 1 {
            return "Swipe for more · Pinch or double-tap to zoom"
        }
        return "Pinch or double-tap to zoom"
    }
}
