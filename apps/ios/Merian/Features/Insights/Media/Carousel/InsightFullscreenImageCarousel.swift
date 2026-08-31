import SwiftUI

struct InsightFullscreenImageCarousel: View {
    let presentation: InsightImageGalleryPresentation
    let dependencies: InsightCarouselDependencies

    @Environment(\.dismiss) private var dismiss
    @State private var selectedItemID: String?
    @State private var isVideoMuted: Bool
    @State private var unavailableVideoItemIDs: Set<String> = []

    init(
        presentation: InsightImageGalleryPresentation,
        dependencies: InsightCarouselDependencies? = nil
    ) {
        self.presentation = presentation
        self.dependencies = dependencies ?? .live
        _isVideoMuted = State(initialValue: presentation.initialVideoMuted)
    }

    private var selectedItem: InsightImageGalleryItem? {
        let fallbackID = presentation.items[
            safe: presentation.initialSelectedIndex
        ]?.id
        let activeID = selectedItemID ?? fallbackID
        return presentation.items.first { $0.id == activeID }
            ?? presentation.items.first
    }

    private var isSelectedVideoUnavailable: Bool {
        guard let selectedItem, selectedItem.source.isVideo else { return false }
        return unavailableVideoItemIDs.contains(selectedItem.id)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(presentation.items) { item in
                        Group {
                            if item.source.isVideo {
                                galleryContent(for: item)
                            } else {
                                ZoomableScrollView {
                                    galleryContent(for: item)
                                }
                            }
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

            topControls
            bottomControls
        }
        .simultaneousGesture(swipeDownToDismissGesture)
        .onAppear {
            selectedItemID = presentation.items[
                safe: presentation.initialSelectedIndex
            ]?.id
        }
    }

    private var swipeDownToDismissGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let verticalDistance = value.translation.height
                let horizontalDistance = abs(value.translation.width)
                let predictedVerticalDistance =
                    value.predictedEndTranslation.height
                let effectiveVerticalDistance = max(
                    verticalDistance,
                    predictedVerticalDistance * 0.55
                )

                guard effectiveVerticalDistance > 70 else { return }
                guard effectiveVerticalDistance
                    > horizontalDistance * 1.2 else { return }

                dismiss()
            }
    }

    private var topControls: some View {
        VStack {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Circle().fill(.white.opacity(0.14)))
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close image viewer")

                Spacer()

                if selectedItem?.source.isVideo == true,
                   !isSelectedVideoUnavailable {
                    Button {
                        isVideoMuted.toggle()
                        dependencies.selectionFeedback(
                            "media.insight.fullscreen.mute.\(isVideoMuted ? "on" : "off")"
                        )
                    } label: {
                        Image(systemName: isVideoMuted
                            ? "speaker.slash.fill"
                            : "speaker.wave.2.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(Circle().fill(.white.opacity(0.14)))
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        isVideoMuted ? "Unmute video" : "Mute video"
                    )
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 16)

            Spacer()
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func galleryContent(for item: InsightImageGalleryItem) -> some View {
        if let accessibilityLabel = item.accessibilityLabel {
            galleryMedia(for: item)
                .accessibilityLabel(accessibilityLabel)
        } else {
            galleryMedia(for: item)
        }
    }

    @ViewBuilder
    private func galleryMedia(for item: InsightImageGalleryItem) -> some View {
        switch item.source {
        case .liveImage(let data):
            FullscreenLiveImageView(data: data)
        case .imagePath(let path):
            AsyncLocalImageView(
                path: path,
                fallbackImageUrl: nil,
                contentMode: .fit,
                unavailableContext: .originalPhoto,
                onImageLoadFailed: nil
            )
        case .videoPath(let path):
            FullscreenVideoPlaybackView(
                path: path,
                isSelected: item.id == selectedItem?.id,
                isMuted: $isVideoMuted,
                dependencies: dependencies,
                onAvailabilityChange: {
                    updateVideoAvailability(
                        itemID: item.id,
                        isUnavailable: $0
                    )
                }
            )
        case .referenceURL(let urlString):
            AsyncLocalImageView(
                path: nil,
                fallbackImageUrl: urlString,
                contentMode: .fit,
                onImageLoadFailed: nil
            )
        }
    }

    private func updateVideoAvailability(
        itemID: String,
        isUnavailable: Bool
    ) {
        if isUnavailable {
            unavailableVideoItemIDs.insert(itemID)
        } else {
            unavailableVideoItemIDs.remove(itemID)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                if let label = selectedItem?.referenceAttributionLabel {
                    Text(label)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule(style: .continuous)
                                .fill(.white.opacity(0.14))
                        }
                        .background(
                            .ultraThinMaterial,
                            in: Capsule(style: .continuous)
                        )
                        .transition(
                            .opacity.combined(with: .move(edge: .bottom))
                        )
                }

                if presentation.items.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(presentation.items) { item in
                            Circle()
                                .fill(item.id == selectedItem?.id
                                    ? Color.white
                                    : Color.white.opacity(0.35))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .animation(
                .spring(response: 0.3, dampingFraction: 0.8),
                value: selectedItem?.id
            )
            .padding(.bottom, 24)
        }
    }
}
