import Foundation
import Testing
import UIKit

@testable import Merian

@Suite("Capture workspace staging", .serialized)
struct CaptureWorkspaceStagingTests {
    @Test func exhaustedImageImportAdmissionBlocksBeforePickerAndCrop() async {
        await Task { @MainActor in
            let admissionManager = ScanAdmissionManager.shared
            let queueManager = OfflineQueueManager.shared
            let previousOnlineState = queueManager.isOnline
            var receivedFlashEligibility: Bool?
            admissionManager.overridingPreview = { flashFallbackEligible in
                receivedFlashEligibility = flashFallbackEligible
                return ScanAdmissionPreview(
                    decision: .dailyQuotaExhausted,
                    effectivePlan: "free",
                    dailyLimit: 1,
                    dailyRemaining: 0
                )
            }
            queueManager.isOnline = true
            defer {
                admissionManager.resetForTesting()
                queueManager.isOnline = previousOnlineState
            }

            let viewModel = CaptureWorkspaceViewModel(
                diContainer: .preview,
                preparedImageLoader: { _ in nil },
                prewarmHeadersOnInit: false
            )
            let shouldPresentPicker = await viewModel.requestImageImportEntryAdmission(
                prospectiveImageCount: 1
            )

            #expect(!shouldPresentPicker)
            #expect(receivedFlashEligibility == true)
            #expect(viewModel.activeSheet == .paywall)
            #expect(viewModel.stagedCapture.isEmpty)
            #expect(viewModel.imageToCrop == nil)
            #expect(!viewModel.isCheckingScanAdmission)
        }.value
    }

    @Test func automaticSingleCaptureFencesTheIdentifyTray() async {
        await MainActor.run {
            let diContainer = AppDIContainer.preview
            let previousConfirmation = diContainer.appSettings.requiresScanConfirmation
            let previousMultiCapture = diContainer.appSettings.isMultiCaptureEnabled
            defer {
                diContainer.appSettings.requiresScanConfirmation = previousConfirmation
                diContainer.appSettings.isMultiCaptureEnabled = previousMultiCapture
            }

            diContainer.appSettings.requiresScanConfirmation = false
            diContainer.appSettings.isMultiCaptureEnabled = false

            let viewModel = CaptureWorkspaceViewModel(
                diContainer: diContainer,
                preparedImageLoader: { _ in nil },
                prewarmHeadersOnInit: false
            )
            viewModel.stagedCapture.images = [StagedImage(
                compressedData: Data([0x01]),
                displayData: Data([0x02]),
                uiImage: UIImage(),
                original: IdentifiableImage(image: UIImage())
            )]

            #expect(viewModel.beginAutomaticStagedSubmissionIfEligible())
            #expect(viewModel.isAutomaticStagedSubmissionPending)
            #expect(!viewModel.shouldPresentActiveScanToolbar)

            viewModel.finishAutomaticStagedSubmissionAttempt()

            #expect(!viewModel.isAutomaticStagedSubmissionPending)
            #expect(viewModel.shouldPresentActiveScanToolbar)

            diContainer.appSettings.requiresScanConfirmation = true
            #expect(!viewModel.beginAutomaticStagedSubmissionIfEligible())
            #expect(viewModel.shouldPresentActiveScanToolbar)

            viewModel.clearStagedCaptureAndCropState()
            #expect(!viewModel.isAutomaticStagedSubmissionPending)
            #expect(!viewModel.shouldPresentActiveScanToolbar)
        }
    }

    @Test func requiredCropStateFencesCaptureChromeBeforePresentation() {
        #expect(CaptureWorkspaceViewModel.shouldSuppressCaptureChromeForCrop(
            hasPendingRequiredGalleryCrop: true,
            isCropPresented: false
        ))
        #expect(CaptureWorkspaceViewModel.shouldSuppressCaptureChromeForCrop(
            hasPendingRequiredGalleryCrop: false,
            isCropPresented: true
        ))
        #expect(!CaptureWorkspaceViewModel.shouldSuppressCaptureChromeForCrop(
            hasPendingRequiredGalleryCrop: false,
            isCropPresented: false
        ))
    }

    @Test func removingStagedAudioOnlyRemovesTheSelectedRecording() async {
        await MainActor.run {
            let firstPath = "staged_audio_remove_\(UUID().uuidString).wav"
            let secondPath = "staged_audio_keep_\(UUID().uuidString).wav"
            let viewModel = CaptureWorkspaceViewModel(
                diContainer: .preview,
                preparedImageLoader: { _ in nil },
                prewarmHeadersOnInit: false
            )
            viewModel.stagedCapture.audios = [
                StagedAudio(filePath: firstPath),
                StagedAudio(filePath: secondPath)
            ]

            viewModel.removeStagedAudio(at: 0)

            #expect(viewModel.stagedCapture.audios.map(\.filePath) == [secondPath])
            viewModel.removeStagedAudio(at: 4)
            #expect(viewModel.stagedCapture.audios.map(\.filePath) == [secondPath])
        }
    }
}
