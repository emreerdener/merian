import SwiftUI

struct FullscreenLiveImageView: View {
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
                ImageDownsampler.downsample(
                    data: imageData,
                    maxSize: 2048
                )
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
