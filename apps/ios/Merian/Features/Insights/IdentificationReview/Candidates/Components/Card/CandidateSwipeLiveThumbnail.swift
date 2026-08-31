import SwiftUI

struct CandidateSwipeLiveThumbnail: View {
    let imageData: Data

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
        }
        .task(id: imageData) {
            let decodedImage: UIImage? = await Task.detached(
                priority: .userInitiated
            ) {
                autoreleasepool {
                    guard let cgImage = ImageDownsampler.downsample(
                        data: imageData,
                        maxSize: 512
                    ) else {
                        return nil
                    }
                    return UIImage(cgImage: cgImage)
                }
            }.value
            guard !Task.isCancelled else { return }
            uiImage = decodedImage
        }
    }
}
