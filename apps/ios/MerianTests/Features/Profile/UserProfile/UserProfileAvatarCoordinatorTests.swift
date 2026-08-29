import PhotosUI
import SwiftUI
import XCTest

@testable import Merian

@MainActor
final class UserProfileAvatarCoordinatorTests: XCTestCase {
    private enum StubError: LocalizedError {
        case failed

        var errorDescription: String? {
            "Avatar preparation failed."
        }
    }

    func testPreparedAvatarPresentationPolicyRequiresCurrentOpenSlot() {
        let requestID = UUID()

        XCTAssertTrue(
            UserProfileAvatarPresentationPolicy.canAcceptPreparedAvatar(
                requestID: requestID,
                currentRequestID: requestID,
                hasActivePresentation: false,
                isCancelled: false
            )
        )
        XCTAssertFalse(
            UserProfileAvatarPresentationPolicy.canAcceptPreparedAvatar(
                requestID: requestID,
                currentRequestID: UUID(),
                hasActivePresentation: false,
                isCancelled: false
            )
        )
        XCTAssertFalse(
            UserProfileAvatarPresentationPolicy.canAcceptPreparedAvatar(
                requestID: requestID,
                currentRequestID: requestID,
                hasActivePresentation: true,
                isCancelled: false
            )
        )
        XCTAssertFalse(
            UserProfileAvatarPresentationPolicy.canAcceptPreparedAvatar(
                requestID: requestID,
                currentRequestID: requestID,
                hasActivePresentation: false,
                isCancelled: true
            )
        )
    }

    func testSelectionCompletionCannotStageOverOccupiedPresentation() async {
        let preparedImage = IdentifiableImage(image: UIImage())
        var pendingPreparation:
            CheckedContinuation<IdentifiableImage?, any Error>?
        var isPresentationSlotAvailable = true
        let coordinator = UserProfileAvatarCoordinator(
            dependencies: makeDependencies(
                prepareCropImage: { _ in
                    try await withCheckedThrowingContinuation {
                        pendingPreparation = $0
                    }
                }
            )
        )

        let selectionTask = coordinator.select(
            PhotosPickerItem(itemIdentifier: "avatar-test-item"),
            isPresentationSlotAvailable: {
                isPresentationSlotAvailable
            }
        )
        while pendingPreparation == nil {
            await Task.yield()
        }

        isPresentationSlotAvailable = false
        pendingPreparation?.resume(returning: preparedImage)
        await selectionTask.value

        XCTAssertNil(coordinator.preparedCropImage)
        XCTAssertNil(coordinator.pendingErrorMessage)
    }

    func testEmptyCropIsRejectedBeforePreparation() {
        var updateCallCount = 0
        let coordinator = UserProfileAvatarCoordinator(
            dependencies: makeDependencies()
        )

        coordinator.upload(
            croppedData: Data(),
            expectedUserID: "account-1",
            currentUserID: { "account-1" },
            updateAvatar: { _ in
                updateCallCount += 1
                return true
            },
            updateFailureMessage: { nil }
        )

        XCTAssertEqual(
            coordinator.pendingErrorMessage,
            "Naturebook could not crop that image."
        )
        XCTAssertEqual(updateCallCount, 0)
        XCTAssertFalse(coordinator.isUploading)
    }

    func testPreparationFailureSurfacesUserFacingError() async {
        let coordinator = UserProfileAvatarCoordinator(
            dependencies: makeDependencies(
                prepareUpload: { _ in throw StubError.failed }
            )
        )

        coordinator.upload(
            croppedData: Data([1]),
            expectedUserID: "account-1",
            currentUserID: { "account-1" },
            updateAvatar: { _ in true },
            updateFailureMessage: { nil }
        )
        while coordinator.isUploading {
            await Task.yield()
        }

        XCTAssertEqual(
            coordinator.pendingErrorMessage,
            "Avatar preparation failed."
        )
    }

    func testServerFailureUsesProfileErrorMessage() async {
        let coordinator = UserProfileAvatarCoordinator(
            dependencies: makeDependencies()
        )

        coordinator.upload(
            croppedData: Data([1]),
            expectedUserID: "account-1",
            currentUserID: { "account-1" },
            updateAvatar: { _ in false },
            updateFailureMessage: { "Server rejected avatar." }
        )
        while coordinator.isUploading {
            await Task.yield()
        }

        XCTAssertEqual(
            coordinator.pendingErrorMessage,
            "Server rejected avatar."
        )
    }

    func testAccountChangeFencesLateUploadFailure() async {
        var currentUserID: String? = "account-1"
        var pendingUpdate: CheckedContinuation<Bool, Never>?
        let coordinator = UserProfileAvatarCoordinator(
            dependencies: makeDependencies()
        )

        coordinator.upload(
            croppedData: Data([1]),
            expectedUserID: currentUserID,
            currentUserID: { currentUserID },
            updateAvatar: { _ in
                await withCheckedContinuation { pendingUpdate = $0 }
            },
            updateFailureMessage: { "Stale failure" }
        )
        while pendingUpdate == nil {
            await Task.yield()
        }

        currentUserID = "account-2"
        pendingUpdate?.resume(returning: false)
        while coordinator.isUploading {
            await Task.yield()
        }

        XCTAssertNil(coordinator.pendingErrorMessage)
    }

    private func makeDependencies(
        prepareCropImage: @escaping @MainActor (
            PhotosPickerItem
        ) async throws -> IdentifiableImage? = { _ in nil },
        prepareUpload: @escaping @Sendable (
            Data
        ) async throws -> PreparedProfileAvatar = { data in
            PreparedProfileAvatar(
                data: data,
                contentType: "image/jpeg",
                fileExtension: "jpg"
            )
        }
    ) -> UserProfileAvatarDependencies {
        UserProfileAvatarDependencies(
            prepareCropImage: prepareCropImage,
            prepareUpload: prepareUpload
        )
    }
}
