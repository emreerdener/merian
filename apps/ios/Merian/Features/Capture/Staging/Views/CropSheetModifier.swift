import SwiftUI

struct CropSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Bindable var viewModel: CaptureWorkspaceViewModel
    var onRequiredCropReadyForSubmit: () -> Void = {}
    var onDismiss: () -> Void = {}

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss) {
            if let identItem = viewModel.imageToCrop {
                ImageCropperView(
                    image: identItem.image,
                    initialScale: identItem.lastCropScale,
                    initialOffset: identItem.lastCropOffset,
                    initialQuarterTurns: identItem.lastCropQuarterTurns,
                    onCrop: { croppedData, finalScale, finalOffset, displaySize, finalQuarterTurns in
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
                            updatedOriginal.lastCropQuarterTurns = finalQuarterTurns
                            updatedOriginal.lastCropScale = finalScale
                            updatedOriginal.lastCropOffset = finalOffset

                            viewModel.stagedCapture.images[editIndex] = existing.replacing(
                                compressedData: croppedData,
                                uiImage: thumbnail,
                                original: updatedOriginal
                            ).replacingFocusRegion(nil)

                            // Re-run against the same immutable source, never the previous
                            // display crop, so reopening cannot compound crop or rotation.
                            // Runs off the main thread; display data updates asynchronously
                            // before the user can tap Submit.
                            let cropSource = existing.original.image
                            let preparation = viewModel.draftSession.beginRelatedWork()
                            viewModel.replaceActiveCropTask(with: Task {
                                var succeeded = false
                                defer {
                                    viewModel.completeDraftOperation(preparation, succeeded: succeeded)
                                }
                                async let detectedFocusRegion = ImageFocusRegionDetector.detect(in: croppedData)
                                async let displayCropped = Task.detached {
                                    return await ImageCropProcessor.generateCrop(
                                        image: cropSource,
                                        displaySize: displaySize,
                                        scale: finalScale,
                                        currentScale: 1.0,
                                        offset: finalOffset,
                                        currentOffset: .zero,
                                        quarterTurns: finalQuarterTurns,
                                        maxPixelSize: Int(ImagePreparationPolicy.displayMaxDimension)
                                    )
                                }.value
                                let (resolvedDisplayCrop, focusRegion) = await (displayCropped, detectedFocusRegion)
                                guard !Task.isCancelled, viewModel.draftSession.contains(preparation) else { return }
                                if let resolvedIndex = viewModel.stagedCapture.images.firstIndex(where: { $0.original.id == targetId }) {
                                    let current = viewModel.stagedCapture.images[resolvedIndex]
                                    let resolvedDisplayData = resolvedDisplayCrop.isEmpty ? croppedData : resolvedDisplayCrop
                                    viewModel.stagedCapture.images[resolvedIndex] = current.replacing(
                                        displayData: resolvedDisplayData
                                    ).replacingFocusRegion(focusRegion)
                                }

                                succeeded = true
                                if isRequiredGalleryCrop {
                                    viewModel.editingCropIndex = nil
                                    viewModel.imageToCrop = nil
                                    viewModel.completeRequiredGalleryCrop(for: targetId)
                                }
                            })
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
                            viewModel.cancelActiveCropTask()
                            if let editIndex = viewModel.stagedCapture.images.firstIndex(where: { $0.original.id == targetId }) {
                                viewModel.stagedCapture.images.remove(at: editIndex)
                                viewModel.resetReviewIfEmpty()
                            }
                            viewModel.editingCropIndex = nil
                            viewModel.imageToCrop = nil
                        }
                    },
                    onConfirmFeedback: {
                        viewModel.triggerMediumFeedback()
                    }
                )
            }
        }
    }
}
