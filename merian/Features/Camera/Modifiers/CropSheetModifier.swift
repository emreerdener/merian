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
                    onCrop: { croppedData, finalScale, finalOffset in
                        if let editIndex = viewModel.editingCropIndex, editIndex < viewModel.activeScannedDatas.count {
                            viewModel.activeScannedDatas[editIndex] = croppedData
                            if let updatedThumb = UIImage(data: croppedData) {
                                viewModel.activeScanImages[editIndex] = updatedThumb
                            }
                            viewModel.activeOriginals[editIndex].lastCropScale = finalScale
                            viewModel.activeOriginals[editIndex].lastCropOffset = finalOffset
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
