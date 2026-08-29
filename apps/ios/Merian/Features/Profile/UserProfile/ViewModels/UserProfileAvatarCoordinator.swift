import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class UserProfileAvatarCoordinator {
    private(set) var preparedCropImage: IdentifiableImage?
    private(set) var pendingErrorMessage: String?
    private(set) var isUploading = false

    private let dependencies: UserProfileAvatarDependencies
    private var selectionRequestID: UUID?
    private var selectionTask: Task<Void, Never>?
    private var uploadRequestID: UUID?
    private var uploadTask: Task<Void, Never>?

    init(dependencies: UserProfileAvatarDependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    @discardableResult
    func select(
        _ item: PhotosPickerItem,
        isPresentationSlotAvailable: @escaping @MainActor () -> Bool
    ) -> Task<Void, Never> {
        cancelSelection()
        let requestID = UUID()
        selectionRequestID = requestID

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if selectionRequestID == requestID {
                    selectionTask = nil
                    if preparedCropImage == nil {
                        selectionRequestID = nil
                    }
                }
            }

            do {
                guard let image = try await dependencies.prepareCropImage(item)
                else {
                    guard canApplySelection(
                        requestID,
                        isPresentationSlotAvailable: isPresentationSlotAvailable
                    ) else { return }
                    pendingErrorMessage =
                        "Naturebook could not load that image."
                    return
                }
                guard canApplySelection(
                    requestID,
                    isPresentationSlotAvailable: isPresentationSlotAvailable
                ) else { return }
                preparedCropImage = image
            } catch is CancellationError {
                return
            } catch {
                guard canApplySelection(
                    requestID,
                    isPresentationSlotAvailable: isPresentationSlotAvailable
                ) else { return }
                pendingErrorMessage = error.localizedDescription
            }
        }
        selectionTask = task
        return task
    }

    func takePreparedCropImage() -> IdentifiableImage? {
        guard selectionRequestID != nil else { return nil }
        let image = preparedCropImage
        preparedCropImage = nil
        selectionRequestID = nil
        return image
    }

    func discardPreparedCropImage() {
        cancelSelection()
    }

    func upload(
        croppedData: Data,
        expectedUserID: String?,
        currentUserID: @escaping @MainActor () -> String?,
        updateAvatar: @escaping @MainActor (
            _ avatar: PreparedProfileAvatar
        ) async -> Bool,
        updateFailureMessage: @escaping @MainActor () -> String?
    ) {
        guard !croppedData.isEmpty else {
            pendingErrorMessage = "Naturebook could not crop that image."
            return
        }

        cancelUpload()
        let requestID = UUID()
        uploadRequestID = requestID
        isUploading = true

        uploadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if uploadRequestID == requestID {
                    uploadRequestID = nil
                    uploadTask = nil
                    isUploading = false
                }
            }

            do {
                let avatar = try await dependencies.prepareUpload(croppedData)
                guard canApplyUpload(
                    requestID,
                    expectedUserID: expectedUserID,
                    currentUserID: currentUserID()
                ) else { return }

                let didUpdate = await updateAvatar(avatar)
                guard canApplyUpload(
                    requestID,
                    expectedUserID: expectedUserID,
                    currentUserID: currentUserID()
                ) else { return }
                guard !didUpdate else { return }

                pendingErrorMessage = updateFailureMessage()
                    ?? "Naturebook could not update your profile picture."
            } catch is CancellationError {
                return
            } catch {
                guard canApplyUpload(
                    requestID,
                    expectedUserID: expectedUserID,
                    currentUserID: currentUserID()
                ) else { return }
                pendingErrorMessage = error.localizedDescription
            }
        }
    }

    func clearPendingError() {
        pendingErrorMessage = nil
    }

    func cancelSelection() {
        selectionRequestID = nil
        selectionTask?.cancel()
        selectionTask = nil
        preparedCropImage = nil
    }

    func cancelUpload() {
        uploadRequestID = nil
        uploadTask?.cancel()
        uploadTask = nil
        isUploading = false
    }

    func cancelAll() {
        cancelSelection()
        cancelUpload()
    }

    private func canApplySelection(
        _ requestID: UUID,
        isPresentationSlotAvailable: @MainActor () -> Bool
    ) -> Bool {
        UserProfileAvatarPresentationPolicy.canAcceptPreparedAvatar(
            requestID: requestID,
            currentRequestID: selectionRequestID,
            hasActivePresentation: !isPresentationSlotAvailable(),
            isCancelled: Task.isCancelled
        )
    }

    private func canApplyUpload(
        _ requestID: UUID,
        expectedUserID: String?,
        currentUserID: String?
    ) -> Bool {
        !Task.isCancelled &&
            uploadRequestID == requestID &&
            currentUserID == expectedUserID
    }
}
