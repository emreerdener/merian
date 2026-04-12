import SwiftUI

struct OriginalCapturePiPView: View {
    @Environment(InferenceEngine.self) private var inferenceEngine
    @State private var decodedImage: UIImage?

    var body: some View {
        Group {
            if let imageData = inferenceEngine.activeDisplayDatas.first {
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
                        .task {
                            let img = await Task.detached(priority: .userInitiated) {
                                autoreleasepool { () -> UIImage? in
                                    if let cgImage = ImageDownsampler.shared.downsample(data: imageData, maxSize: 512) {
                                        return UIImage(cgImage: cgImage)
                                    }
                                    return nil
                                }
                            }.value
                            decodedImage = img
                        }
                }
            } else if let path = inferenceEngine.validHistoricImagePaths.first {
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
