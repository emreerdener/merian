import SwiftUI

struct CropSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Bindable var viewModel: CameraViewModel

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            if let identItem = viewModel.imageToCrop {
                ImageCropperView(
                    image: identItem.image,
                    initialScale: identItem.lastCropScale,
                    initialOffset: identItem.lastCropOffset,
                    onCrop: { croppedData, finalScale, finalOffset, displaySize in
                        if let editIndex = viewModel.editingCropIndex,
                           editIndex < viewModel.stagedCapture.images.count {

                            let existing = viewModel.stagedCapture.images[editIndex]

                            // Rebuild the thumbnail from the cropped compressed data.
                            let thumbnail: UIImage
                            if let cgImage = autoreleasepool(invoking: {
                                ImageDownsampler.downsample(data: croppedData, maxSize: 512)
                            }) {
                                thumbnail = UIImage(cgImage: cgImage)
                            } else {
                                thumbnail = existing.uiImage
                            }

                            // Persist the crop geometry back into the original so a second
                            // crop session opens at the last confirmed position.
                            var updatedOriginal = existing.original
                            updatedOriginal.lastCropScale = finalScale
                            updatedOriginal.lastCropOffset = finalOffset

                            viewModel.stagedCapture.images[editIndex] = StagedImage(
                                compressedData: croppedData,
                                displayData: existing.displayData, // replaced asynchronously below
                                uiImage: thumbnail,
                                original: updatedOriginal
                            )

                            // Re-run the same crop geometry on the 2048px display image so
                            // the scan library stores what Gemini actually analyzed.
                            // Runs off the main thread; display data updates asynchronously
                            // before the user can tap Submit.
                            let capturedDisplayData = existing.displayData
                            let capturedIndex = editIndex
                            Task {
                                let displayCropped = await Task.detached {
                                    let src: UIImage? = autoreleasepool {
                                        guard let cgImage = ImageDownsampler.downsample(data: capturedDisplayData, maxSize: 2048) else { return nil }
                                        return UIImage(cgImage: cgImage)
                                    }
                                    guard let image = src else { return Data() }

                                    return await ImageCropProcessor.generateCrop(
                                        image: image,
                                        displaySize: displaySize,
                                        scale: finalScale,
                                        currentScale: 1.0,
                                        offset: finalOffset,
                                        currentOffset: .zero,
                                        maxPixelSize: nil
                                    )
                                }.value
                                guard !displayCropped.isEmpty,
                                      capturedIndex < viewModel.stagedCapture.images.count else { return }
                                let current = viewModel.stagedCapture.images[capturedIndex]
                                viewModel.stagedCapture.images[capturedIndex] = StagedImage(
                                    compressedData: current.compressedData,
                                    displayData: displayCropped,
                                    uiImage: current.uiImage,
                                    original: current.original
                                )
                            }
                        }
                        viewModel.editingCropIndex = nil
                        viewModel.imageToCrop = nil
                    },
                    onCancel: {
                        viewModel.editingCropIndex = nil
                        viewModel.imageToCrop = nil
                    },
                    onDelete: {
                        if let editIndex = viewModel.editingCropIndex,
                           editIndex < viewModel.stagedCapture.images.count {
                            viewModel.stagedCapture.images.remove(at: editIndex)
                        }
                        viewModel.editingCropIndex = nil
                        viewModel.imageToCrop = nil
                    }
                )
            }
        }
    }
}
