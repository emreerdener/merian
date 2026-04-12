import SwiftUI

struct OriginalCaptureExpandedView: View {
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.dismiss) private var dismiss
    @State private var decodedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Group {
                if let imageData = inferenceEngine.activeDisplayDatas.first {
                    if let img = decodedImage {
                        ZoomableScrollView {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                        }
                    } else {
                        ProgressView().tint(.white)
                            .task {
                                let img = await Task.detached(priority: .userInitiated) {
                                    autoreleasepool { UIImage(data: imageData) }
                                }.value
                                decodedImage = img
                            }
                    }
                } else if let path = inferenceEngine.validHistoricImagePaths.first {
                    ZoomableScrollView {
                        AsyncLocalImageView(
                            path: path,
                            fallbackImageUrl: nil,
                            onImageLoadFailed: nil
                        )
                        .scaledToFit()
                    }
                } else {
                    Text("Image unavailable")
                        .foregroundColor(.white)
                }
            }
            .ignoresSafeArea()
            
            VStack {
                HStack {
                    Spacer()
                     Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                     .padding()
                }
                Spacer()
            }
        }
    }
}
