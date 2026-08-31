import SwiftUI

struct OriginalCapturePiPView: View {
    @Environment(InferenceEngine.self) private var inferenceEngine
    @State private var decodedImage: UIImage?

    var body: some View {
        Group {
            if let imageData = inferenceEngine.activeMedia.liveImageData {
                let presentationGeneration =
                    inferenceEngine.scanPresentationGeneration
                Group {
                    if let img = decodedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.black.opacity(0.8)
                            .overlay {
                                ProgressView()
                                    .tint(.white)
                            }
                    }
                }
                .task(id: presentationGeneration) {
                    let image = await Task.detached(priority: .userInitiated) {
                        autoreleasepool { () -> UIImage? in
                            if let cgImage = ImageDownsampler.downsample(
                                data: imageData,
                                maxSize: 512
                            ) {
                                return UIImage(cgImage: cgImage)
                            }
                            return nil
                        }
                    }.value
                    guard !Task.isCancelled,
                          inferenceEngine.scanPresentationGeneration ==
                            presentationGeneration else {
                        return
                    }
                    decodedImage = image
                }
            } else if let path = inferenceEngine.activeMedia.imagePathsForUpload.first {
                AsyncLocalImageView(
                    path: path,
                    fallbackImageUrl: nil,
                    onImageLoadFailed: nil
                )
            } else {
                Color.black.opacity(0.8)
            }
        }
    }
}
