import SwiftUI

struct CropSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Bindable var viewModel: CaptureWorkspaceViewModel
    var onRequiredCropReadyForSubmit: () -> Void = {}

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            if let identItem = viewModel.imageToCrop {
                ImageCropperView(
                    image: identItem.image,
                    initialScale: identItem.lastCropScale,
                    initialOffset: identItem.lastCropOffset,
                    onCrop: { croppedData, finalScale, finalOffset, displaySize in
                        let targetId = identItem.id
                        let isRequiredGalleryCrop = viewModel.isRequiredGalleryCrop(targetId)
                        if let editIndex = viewModel.stagedCapture.images.firstIndex(where: { $0.original.id == targetId }) {

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

                            viewModel.stagedCapture.images[editIndex] = existing.replacing(
                                compressedData: croppedData,
                                uiImage: thumbnail,
                                original: updatedOriginal
                            ).replacingFocusRegion(nil)

                            // Re-run the same crop geometry on the 2048px display image so
                            // the scan library stores what Gemini actually analyzed.
                            // Runs off the main thread; display data updates asynchronously
                            // before the user can tap Submit.
                            let capturedDisplayData = existing.displayData
                            viewModel.activeCropTask?.cancel()
                            viewModel.activeCropTask = Task {
                                async let detectedFocusRegion = ImageFocusRegionDetector.detect(in: croppedData)
                                async let displayCropped = Task.detached {
                                    let src = ImageDownsampler.downsampledUIImage(data: capturedDisplayData, maxSize: 2048)
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
                                let (resolvedDisplayCrop, focusRegion) = await (displayCropped, detectedFocusRegion)
                                guard !Task.isCancelled else { return }
                                if let resolvedIndex = viewModel.stagedCapture.images.firstIndex(where: { $0.original.id == targetId }) {
                                    let current = viewModel.stagedCapture.images[resolvedIndex]
                                    let resolvedDisplayData = resolvedDisplayCrop.isEmpty ? croppedData : resolvedDisplayCrop
                                    viewModel.stagedCapture.images[resolvedIndex] = current.replacing(
                                        displayData: resolvedDisplayData
                                    ).replacingFocusRegion(focusRegion)
                                }

                                if isRequiredGalleryCrop {
                                    viewModel.editingCropIndex = nil
                                    viewModel.imageToCrop = nil
                                    if viewModel.completeRequiredGalleryCrop(for: targetId) {
                                        onRequiredCropReadyForSubmit()
                                    }
                                }
                            }
                        } else if isRequiredGalleryCrop {
                            viewModel.cancelRequiredGalleryCrop(for: targetId)
                        }

                        if !isRequiredGalleryCrop {
                            viewModel.editingCropIndex = nil
                            viewModel.imageToCrop = nil
                        }
                    },
                    onCancel: {
                        let targetId = identItem.id
                        if viewModel.isRequiredGalleryCrop(targetId) {
                            viewModel.cancelRequiredGalleryCrop(for: targetId)
                        } else {
                            viewModel.editingCropIndex = nil
                            viewModel.imageToCrop = nil
                        }
                    },
                    onDelete: {
                        let targetId = identItem.id
                        if viewModel.isRequiredGalleryCrop(targetId) {
                            viewModel.cancelRequiredGalleryCrop(for: targetId)
                        } else {
                            viewModel.activeCropTask?.cancel()
                            if let editIndex = viewModel.stagedCapture.images.firstIndex(where: { $0.original.id == targetId }) {
                                viewModel.stagedCapture.images.remove(at: editIndex)
                            }
                            viewModel.editingCropIndex = nil
                            viewModel.imageToCrop = nil
                        }
                    }
                )
            }
        }
    }
}
