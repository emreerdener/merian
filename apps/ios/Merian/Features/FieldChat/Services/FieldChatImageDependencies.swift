import UIKit

@MainActor
struct FieldChatImageDependencies {
    let load: @MainActor (FieldChatMedia.Source, Int) async -> UIImage?

    static var live: Self {
        let images = AsyncLocalImageDependencies.live
        return Self { source, maxDimension in
            switch source {
            case .path(let path):
                return await images.loadImage(path, nil, maxDimension)
            case .liveImage(let data):
                let prepared = try? await DetachedWork.value(
                    priority: .utility, category: .imagePreparation
                ) {
                    autoreleasepool {
                        ImageDownsampler.downsample(data: data, maxSize: CGFloat(maxDimension))
                            .map { SendableCGImage(image: $0) }
                    }
                }
                guard let prepared, !Task.isCancelled else { return nil }
                return UIImage(cgImage: prepared.image)
            }
        }
    }
}
