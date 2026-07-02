import SwiftUI

struct InsightFullscreenImageCarousel: View {
    let presentation: InsightImageGalleryPresentation

    @Environment(\.dismiss) private var dismiss
    @State private var selectedItemID: String?

    private var selectedItem: InsightImageGalleryItem? {
        let fallbackID = presentation.items[safe: presentation.initialSelectedIndex]?.id
        let activeID = selectedItemID ?? fallbackID
        return presentation.items.first { $0.id == activeID } ?? presentation.items.first
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(presentation.items) { item in
                        ZoomableScrollView {
                            galleryImage(for: item)
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
            selectedItemID = presentation.items[safe: presentation.initialSelectedIndex]?.id
        }
    }

    private var swipeDownToDismissGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let verticalDistance = value.translation.height
                let horizontalDistance = abs(value.translation.width)
                let predictedVerticalDistance = value.predictedEndTranslation.height
                let effectiveVerticalDistance = max(verticalDistance, predictedVerticalDistance * 0.55)

                guard effectiveVerticalDistance > 70 else { return }
                guard effectiveVerticalDistance > horizontalDistance * 1.2 else { return }

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
            }
            .padding(.top, 12)
            .padding(.horizontal, 16)

            Spacer()
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func galleryImage(for item: InsightImageGalleryItem) -> some View {
        switch item.source {
        case .liveImage(let data):
            FullscreenLiveImageView(data: data)
        case .imagePath(let path):
            AsyncLocalImageView(
                path: path,
                fallbackImageUrl: nil,
                contentMode: .fit,
                onImageLoadFailed: nil
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
                        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if presentation.items.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(presentation.items) { item in
                            Circle()
                                .fill(item.id == selectedItem?.id ? Color.white : Color.white.opacity(0.35))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedItem?.id)
            .padding(.bottom, 24)
        }
    }
}

private struct FullscreenLiveImageView: View {
    let data: Data

    @State private var decodedImage: UIImage?
    @State private var decodedImageKey: Int?

    var body: some View {
        Group {
            if let decodedImage {
                Image(uiImage: decodedImage)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: data.hashValue) {
            await loadImageIfNeeded()
        }
    }

    @MainActor
    private func loadImageIfNeeded() async {
        let key = data.hashValue
        if decodedImageKey == key, decodedImage != nil { return }

        let cacheKey = NSNumber(value: key)
        if let cached = liveCaptureCache.object(forKey: cacheKey) {
            decodedImage = cached
            decodedImageKey = key
            return
        }

        let imageData = data
        let preparedImage = try? await DetachedWork.value(
            priority: .utility,
            category: .imagePreparation
        ) {
            autoreleasepool {
                ImageDownsampler.downsample(data: imageData, maxSize: 2048)
                    .map { SendableCGImage(image: $0) }
            }
        }

        guard let preparedImage, !Task.isCancelled else { return }
        let image = UIImage(cgImage: preparedImage.image)
        let cost = Int(image.size.width * image.size.height * 4)
        liveCaptureCache.setObject(image, forKey: cacheKey, cost: cost)
        decodedImage = image
        decodedImageKey = key
    }
}
