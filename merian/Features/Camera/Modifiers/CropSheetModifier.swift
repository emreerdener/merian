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
                        if let editIndex = viewModel.editingCropIndex, editIndex < viewModel.activeScannedDatas.count {
                            viewModel.activeScannedDatas[editIndex] = croppedData
                            if let cgImage = autoreleasepool(invoking: { ImageDownsampler.shared.downsample(data: croppedData, maxSize: 512) }) {
                                viewModel.activeScanImages[editIndex] = UIImage(cgImage: cgImage)
                            }
                            viewModel.activeOriginals[editIndex].lastCropScale = finalScale
                            viewModel.activeOriginals[editIndex].lastCropOffset = finalOffset

                            // Re-run the same crop geometry on the 2048px display image so
                            // the scan library stores what Gemini actually analyzed.
                            // Runs off the main thread; display data updates asynchronously
                            // before the user can tap Submit.
                            if editIndex < viewModel.activeDisplayDatas.count {
                                let capturedDisplayData = viewModel.activeDisplayDatas[editIndex]
                                let capturedIndex = editIndex
                                Task {
                                    let displayCropped = await Task.detached {
                                        let src: UIImage? = autoreleasepool {
                                            guard let cgImage = ImageDownsampler.shared.downsample(data: capturedDisplayData, maxSize: 2048) else { return nil }
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
                                    guard !displayCropped.isEmpty else { return }
                                    viewModel.activeDisplayDatas[capturedIndex] = displayCropped
                                }
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
                        if let editIndex = viewModel.editingCropIndex, editIndex < viewModel.activeScannedDatas.count {
                            viewModel.activeScannedDatas.remove(at: editIndex)
                            viewModel.activeScanImages.remove(at: editIndex)
                            viewModel.activeOriginals.remove(at: editIndex)
                        }
                        viewModel.editingCropIndex = nil
                        viewModel.imageToCrop = nil
                    }
                )
            }
        }
    }
}
