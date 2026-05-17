import SwiftUI

// MARK: - Live Capture Page
let liveCaptureCache: NSCache<NSNumber, UIImage> = {
    let c = NSCache<NSNumber, UIImage>()
    c.totalCostLimit = 50 * 1024 * 1024  // 50 MB
    c.countLimit = 5
    return c
}()

struct LiveCapturePageView: View {
    let data: Data

    @State private var decodedImage: UIImage?
    @State private var decodedImageKey: Int?

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

        guard let preparedImage else { return }
        let img = UIImage(cgImage: preparedImage.image)
        if !Task.isCancelled {
            let cost = Int(img.size.width * img.size.height * 4)
            liveCaptureCache.setObject(img, forKey: cacheKey, cost: cost)
            decodedImage = img
            decodedImageKey = key
        }
    }

    var body: some View {
        Group {
            if let img = decodedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: data.hashValue) {
            await loadImageIfNeeded()
        }
    }
}
