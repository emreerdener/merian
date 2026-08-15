import CoreLocation
import Testing
import UIKit

@testable import Merian

@Suite("StagedCapture", .serialized)
struct StagedCaptureTests {

    @Test func connectivityUnavailableAdmissionSelectsQueueOnlyRoute() {
        func wrapped(_ error: Error, layers: Int) -> Error {
            (0..<layers).reduce(error) { underlyingError, layer in
                NSError(
                    domain: "ScanAdmissionTransportWrapper.\(layer)",
                    code: layer,
                    userInfo: [NSUnderlyingErrorKey: underlyingError]
                )
            }
        }

        let reviewedConnectivityCodes: [URLError.Code] = [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .notConnectedToInternet,
            .internationalRoamingOff,
            .callIsActive,
            .dataNotAllowed,
            .backgroundSessionWasDisconnected,
            .cannotLoadFromNetwork
        ]
        for code in reviewedConnectivityCodes {
            #expect(ScanConnectivityFailurePolicy.isQueueOnlyAdmissionFailure(
                URLError(code)
            ))
        }

        let wrappedOfflineError = NSError(
            domain: "ScanAdmissionTransportWrapper",
            code: 1,
            userInfo: [
                NSUnderlyingErrorKey: URLError(.notConnectedToInternet)
            ]
        )
        #expect(ScanConnectivityFailurePolicy.isQueueOnlyAdmissionFailure(
            wrappedOfflineError
        ))
        #expect(ScanConnectivityFailurePolicy.isQueueOnlyAdmissionFailure(
            wrapped(URLError(.notConnectedToInternet), layers: 3)
        ))
        #expect(!ScanConnectivityFailurePolicy.isQueueOnlyAdmissionFailure(
            wrapped(URLError(.notConnectedToInternet), layers: 4)
        ))

        let policyFailureCodes: [URLError.Code] = [
            .userCancelledAuthentication,
            .userAuthenticationRequired,
            .appTransportSecurityRequiresSecureConnection,
            .serverCertificateHasBadDate,
            .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid,
            .clientCertificateRejected,
            .clientCertificateRequired
        ]
        let admissionVetoCodes: [URLError.Code] = [
            .cancelled,
            .secureConnectionFailed
        ] + policyFailureCodes
        for failClosedCode in admissionVetoCodes {
            #expect(!ScanConnectivityFailurePolicy.isQueueOnlyAdmissionFailure(
                URLError(failClosedCode)
            ))
        }
        #expect(ScanConnectivityFailurePolicy.isDurableRecoveryFailure(
            URLError(.secureConnectionFailed)
        ))
        #expect(!ScanConnectivityFailurePolicy.isDurableRecoveryFailure(
            URLError(.serverCertificateUntrusted)
        ))

        let wrappedAdmissionTLSFailure = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.secureConnectionFailed.rawValue,
            userInfo: [
                NSUnderlyingErrorKey: URLError(.notConnectedToInternet)
            ]
        )
        #expect(!ScanConnectivityFailurePolicy.isQueueOnlyAdmissionFailure(
            wrappedAdmissionTLSFailure
        ))
        #expect(ScanConnectivityFailurePolicy.isDurableRecoveryFailure(
            wrappedAdmissionTLSFailure
        ))

        for policyCode in policyFailureCodes {
            let wrappedPolicyFailure = NSError(
                domain: NSURLErrorDomain,
                code: URLError.Code.timedOut.rawValue,
                userInfo: [NSUnderlyingErrorKey: URLError(policyCode)]
            )
            #expect(!ScanConnectivityFailurePolicy.isQueueOnlyAdmissionFailure(
                wrappedPolicyFailure
            ))
            #expect(!ScanConnectivityFailurePolicy.isDurableRecoveryFailure(
                wrappedPolicyFailure
            ))
        }

        let deepestInspectedPolicyFailure = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.timedOut.rawValue,
            userInfo: [
                NSUnderlyingErrorKey: wrapped(
                    URLError(.serverCertificateUntrusted),
                    layers: 2
                )
            ]
        )
        #expect(!ScanConnectivityFailurePolicy.isQueueOnlyAdmissionFailure(
            deepestInspectedPolicyFailure
        ))
        #expect(!ScanConnectivityFailurePolicy.isDurableRecoveryFailure(
            deepestInspectedPolicyFailure
        ))

        let wrappedCertificateFailure = NSError(
            domain: NSURLErrorDomain,
            code: URLError.Code.secureConnectionFailed.rawValue,
            userInfo: [
                NSUnderlyingErrorKey: URLError(.serverCertificateUntrusted)
            ]
        )
        #expect(!ScanConnectivityFailurePolicy.isDurableRecoveryFailure(
            wrappedCertificateFailure
        ))

        #expect(CaptureScanAdmissionPolicy.resolve(
            isOnline: true,
            canStartLocally: true,
            previewResult: .connectivityUnavailable
        ) == .proceed(.queued))
        #expect(CaptureScanAdmissionPolicy.resolve(
            isOnline: true,
            canStartLocally: false,
            previewResult: .connectivityUnavailable
        ) == .paywall)
        #expect(CaptureScanAdmissionPolicy.resolve(
            isOnline: true,
            canStartLocally: true,
            previewResult: .unavailable
        ) == .retryRequired)
    }

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
            #expect(!CaptureWorkspaceViewModel.isImageImportFlashFallbackEligible(
                existingItemCount: 0,
                prospectiveImageCount: 2,
                isRefining: false
            ))
            #expect(!CaptureWorkspaceViewModel.isImageImportFlashFallbackEligible(
                existingItemCount: 1,
                prospectiveImageCount: 1,
                isRefining: false
            ))
            #expect(!CaptureWorkspaceViewModel.isImageImportFlashFallbackEligible(
                existingItemCount: 0,
                prospectiveImageCount: 1,
                isRefining: true
            ))
        }.value
    }

    @Test func automaticSingleCaptureNeverPresentsIdentifyBeforeSubmission() async {
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

            // Required gallery media is staged before SwiftUI mounts the crop
            // cover. That pending state must suppress the capture chrome even
            // in the render before imageToCrop becomes visible.
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
    }

    @Test func liveImageLatencyOptimizationExcludesGalleryAudioAndVideo() {
        #expect(CaptureWorkspaceViewModel.shouldOptimizeLiveImageAnalysis(
            hasStillImage: true,
            hasAudio: false,
            hasVideo: false,
            isGalleryPhoto: false
        ))
        #expect(!CaptureWorkspaceViewModel.shouldOptimizeLiveImageAnalysis(
            hasStillImage: true,
            hasAudio: false,
            hasVideo: false,
            isGalleryPhoto: true
        ))
        #expect(!CaptureWorkspaceViewModel.shouldOptimizeLiveImageAnalysis(
            hasStillImage: true,
            hasAudio: true,
            hasVideo: false,
            isGalleryPhoto: false
        ))
        #expect(!CaptureWorkspaceViewModel.shouldOptimizeLiveImageAnalysis(
            hasStillImage: false,
            hasAudio: false,
            hasVideo: true,
            isGalleryPhoto: false
        ))
    }

    @Test func preferredGoalRequiresCameraOnlyStillMedia() {
        let preferredGoal = FieldTripPreferredGoal(
            userFieldTripId: "outing",
            itemId: "butterfly"
        )

        #expect(CaptureWorkspaceViewModel.preferredGoalForSubmission(
            preferredGoal,
            hasCameraStill: true,
            hasGalleryStill: false,
            hasAudio: false,
            hasVideo: false
        ) == preferredGoal)
        #expect(CaptureWorkspaceViewModel.preferredGoalForSubmission(
            preferredGoal,
            hasCameraStill: true,
            hasGalleryStill: true,
            hasAudio: false,
            hasVideo: false
        ) == nil)
        #expect(CaptureWorkspaceViewModel.preferredGoalForSubmission(
            preferredGoal,
            hasCameraStill: true,
            hasGalleryStill: false,
            hasAudio: true,
            hasVideo: false
        ) == nil)
        #expect(CaptureWorkspaceViewModel.preferredGoalForSubmission(
            preferredGoal,
            hasCameraStill: false,
            hasGalleryStill: false,
            hasAudio: false,
            hasVideo: true
        ) == nil)
    }

    // MARK: - isEmpty

    @Test func isEmptyWhenAllModalitiesAreEmpty() {
        let capture = StagedCapture()
        #expect(capture.isEmpty)
    }

    @Test func isEmptyFalseWhenImagesPresent() {
        var capture = StagedCapture()
        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage())
        )
        capture.images.append(image)
        #expect(!capture.isEmpty)
    }

    @Test func isEmptyFalseWhenAudiosPresent() {
        var capture = StagedCapture()
        capture.audios.append(StagedAudio(filePath: "recording.wav"))
        #expect(!capture.isEmpty)
    }

    @Test func isEmptyFalseWhenObservationContextsPresent() {
        var capture = StagedCapture()
        capture.observationContexts.append(
            StagedObservationContext(context: ObservationContext(freeText: "Yellow wings"))
        )
        #expect(!capture.isEmpty)
    }

    // MARK: - isMultiModal

    @Test func isMultiModalFalseForImagesOnly() {
        var capture = StagedCapture()
        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage())
        )
        capture.images.append(image)
        #expect(!capture.isMultiModal)
    }

    @Test func isMultiModalFalseForAudiosOnly() {
        var capture = StagedCapture()
        capture.audios.append(StagedAudio(filePath: "bird.wav"))
        #expect(!capture.isMultiModal)
    }

    @Test func isMultiModalFalseForContextsOnly() {
        var capture = StagedCapture()
        capture.observationContexts.append(
            StagedObservationContext(context: ObservationContext(freeText: "Small brown beetle"))
        )
        #expect(!capture.isMultiModal)
    }

    @Test func isMultiModalTrueForImagesAndAudios() {
        var capture = StagedCapture()
        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage())
        )
        capture.images.append(image)
        capture.audios.append(StagedAudio(filePath: "sound.wav"))
        #expect(capture.isMultiModal)
    }

    @Test func isMultiModalTrueForImagesAndContexts() {
        var capture = StagedCapture()
        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage())
        )
        capture.images.append(image)
        capture.observationContexts.append(
            StagedObservationContext(context: ObservationContext(freeText: "Large wings"))
        )
        #expect(capture.isMultiModal)
    }

    @Test func isMultiModalTrueForAudiosAndContexts() {
        var capture = StagedCapture()
        capture.audios.append(StagedAudio(filePath: "frog.wav"))
        capture.observationContexts.append(
            StagedObservationContext(context: ObservationContext(freeText: "Nocturnal call"))
        )
        #expect(capture.isMultiModal)
    }

    @Test func isMultiModalTrueForAllThreeModalities() {
        var capture = StagedCapture()
        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage())
        )
        capture.images.append(image)
        capture.audios.append(StagedAudio(filePath: "call.wav"))
        capture.observationContexts.append(
            StagedObservationContext(context: ObservationContext(freeText: "Spotted on a leaf"))
        )
        #expect(capture.isMultiModal)
    }

    // MARK: - clearAll

    @Test func clearAllResetsAllModalities() {
        var capture = StagedCapture()
        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage())
        )
        capture.images.append(image)
        capture.audios.append(StagedAudio(filePath: "call.wav"))
        capture.videos.append(StagedVideo(filePath: "clip.mp4", sampledImages: [image], audioFilePath: "clip-audio.wav"))
        capture.observationContexts.append(
            StagedObservationContext(context: ObservationContext(freeText: "Green body"))
        )
        #expect(!capture.isEmpty)

        capture.clearAll()
        #expect(capture.isEmpty)
        #expect(capture.images.isEmpty)
        #expect(capture.audios.isEmpty)
        #expect(capture.videos.isEmpty)
        #expect(capture.observationContexts.isEmpty)
    }

    @Test func discardableLocalMediaFilePathsIncludesAudioVideoAndVideoAudio() {
        var capture = StagedCapture()
        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage())
        )

        capture.audios.append(StagedAudio(filePath: "standalone.wav"))
        capture.videos.append(
            StagedVideo(
                filePath: "/tmp/video-playback.mp4",
                sampledImages: [image],
                audioFilePath: "video-audio.wav"
            )
        )

        #expect(
            Set(capture.discardableLocalMediaFilePaths) == [
                "standalone.wav",
                "/tmp/video-playback.mp4",
                "video-audio.wav"
            ],
            "Cancel cleanup must include standalone audio, playback video, and extracted video audio"
        )
        #expect(
            Set(capture.submissionMediaTimeline.discardableLocalMediaFilePaths) == [
                "standalone.wav",
                "/tmp/video-playback.mp4",
                "video-audio.wav"
            ],
            "Submission snapshots need the same cleanup list when queue ownership fails"
        )
    }

    @Test func removeStagedAudioRemovesOnlyTheSelectedRecording() async {
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

    @Test func availableSlotsUsesTotalMixedItemCount() {
        var capture = StagedCapture()
        capture.audios.append(StagedAudio(filePath: "bird.wav"))
        capture.observationContexts.append(
            StagedObservationContext(context: ObservationContext(freeText: "Perched in reeds"))
        )

        #expect(capture.totalItemCount == 2)
        #expect(capture.availableSlots(limit: stagedCaptureCapacity) == 0)
        #expect(capture.isAtCapacity(limit: stagedCaptureCapacity))
    }

    @Test func submissionMediaTimelinePreservesChronologicalMixedOrder() {
        var capture = StagedCapture()

        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage()),
            addedAt: Date(timeIntervalSince1970: 20)
        )
        capture.images.append(image)
        capture.audios.append(
            StagedAudio(filePath: "call.wav", addedAt: Date(timeIntervalSince1970: 10))
        )
        capture.observationContexts.append(
            StagedObservationContext(
                context: ObservationContext(freeText: "Bright yellow body"),
                addedAt: Date(timeIntervalSince1970: 30)
            )
        )

        let timeline = capture.submissionMediaTimeline
        #expect(timeline.count == 3)

        if case .audio(let audioPath) = timeline[0] {
            #expect(audioPath == "call.wav")
        } else {
            Issue.record("First timeline item must preserve the staged audio clip")
        }

        if case .image(let index) = timeline[1] {
            #expect(index == 0)
        } else {
            Issue.record("Second timeline item must preserve the staged image")
        }

        if case .description(let context) = timeline[2] {
            #expect(context.freeText == "Bright yellow body")
        } else {
            Issue.record("Third timeline item must preserve the staged description")
        }
    }

    @Test func stagedImageReplacingPreservesChronologicalInsertionTime() {
        let originalAddedAt = Date(timeIntervalSince1970: 20)
        let historicalCaptureDate = Date(timeIntervalSince1970: 10)
        var originalImage = IdentifiableImage(
            image: UIImage(),
            environmentContext: EnvironmentContext(
                location: CLLocation(latitude: 41.8781, longitude: -87.6298),
                locationName: nil,
                weatherCondition: nil,
                weatherTemperature: nil,
                captureDate: historicalCaptureDate
            ),
            isFromGallery: true
        )
        originalImage.lastCropScale = 1.2
        let stagedImage = StagedImage(
            compressedData: Data([0x01]),
            displayData: Data([0x02]),
            uiImage: UIImage(),
            original: originalImage,
            addedAt: originalAddedAt
        )

        var croppedOriginal = originalImage
        croppedOriginal.lastCropScale = 2.0
        let replacement = stagedImage.replacing(
            compressedData: Data([0x03]),
            displayData: Data([0x04]),
            uiImage: UIImage(),
            original: croppedOriginal
        )

        #expect(replacement.addedAt == originalAddedAt)
        #expect(replacement.compressedData == Data([0x03]))
        #expect(replacement.displayData == Data([0x04]))
        #expect(replacement.original.lastCropScale == 2.0)
        #expect(replacement.original.isFromGallery)
        #expect(replacement.original.environmentContext?.captureDate == historicalCaptureDate)
        #expect(replacement.original.environmentContext?.location?.coordinate.latitude == 41.8781)
        #expect(replacement.original.environmentContext?.location?.coordinate.longitude == -87.6298)
    }

    @Test func submissionMediaTimelineSupportsAllowedCombinationMatrix() {
        func makeImage(addedAt: TimeInterval) -> StagedImage {
            StagedImage(
                compressedData: Data([0x00]),
                displayData: Data([0x00]),
                uiImage: UIImage(),
                original: IdentifiableImage(image: UIImage()),
                addedAt: Date(timeIntervalSince1970: addedAt)
            )
        }

        let descriptionA = ObservationContext(freeText: "description A")
        let descriptionB = ObservationContext(freeText: "description B")

        struct Scenario {
            let name: String
            let capture: StagedCapture
            let expectedCount: Int

            init(_ name: String, _ capture: StagedCapture, _ expectedCount: Int) {
                self.name = name
                self.capture = capture
                self.expectedCount = expectedCount
            }
        }

        let scenarios: [Scenario] = [
            .init(
                "audio only",
                StagedCapture(
                    images: [],
                    audios: [StagedAudio(filePath: "audio_only.wav", addedAt: Date(timeIntervalSince1970: 10))],
                    observationContexts: [],
                    lastSubmitTime: nil
                ),
                1
            ),
            .init(
                "audio and audio",
                StagedCapture(
                    images: [],
                    audios: [
                        StagedAudio(filePath: "audio_a.wav", addedAt: Date(timeIntervalSince1970: 10)),
                        StagedAudio(filePath: "audio_b.wav", addedAt: Date(timeIntervalSince1970: 20))
                    ],
                    observationContexts: [],
                    lastSubmitTime: nil
                ),
                2
            ),
            .init(
                "audio and description",
                StagedCapture(
                    images: [],
                    audios: [StagedAudio(filePath: "audio_description.wav", addedAt: Date(timeIntervalSince1970: 10))],
                    observationContexts: [StagedObservationContext(context: descriptionA, addedAt: Date(timeIntervalSince1970: 20))],
                    lastSubmitTime: nil
                ),
                2
            ),
            .init(
                "audio and image",
                StagedCapture(
                    images: [makeImage(addedAt: 20)],
                    audios: [StagedAudio(filePath: "audio_image.wav", addedAt: Date(timeIntervalSince1970: 10))],
                    observationContexts: [],
                    lastSubmitTime: nil
                ),
                2
            ),
            .init(
                "description only",
                StagedCapture(
                    images: [],
                    audios: [],
                    observationContexts: [StagedObservationContext(context: descriptionA, addedAt: Date(timeIntervalSince1970: 10))],
                    lastSubmitTime: nil
                ),
                1
            ),
            .init(
                "description and description",
                StagedCapture(
                    images: [],
                    audios: [],
                    observationContexts: [
                        StagedObservationContext(context: descriptionA, addedAt: Date(timeIntervalSince1970: 10)),
                        StagedObservationContext(context: descriptionB, addedAt: Date(timeIntervalSince1970: 20))
                    ],
                    lastSubmitTime: nil
                ),
                2
            ),
            .init(
                "description and image",
                StagedCapture(
                    images: [makeImage(addedAt: 20)],
                    audios: [],
                    observationContexts: [StagedObservationContext(context: descriptionA, addedAt: Date(timeIntervalSince1970: 10))],
                    lastSubmitTime: nil
                ),
                2
            ),
            .init(
                "image only",
                StagedCapture(
                    images: [makeImage(addedAt: 10)],
                    audios: [],
                    observationContexts: [],
                    lastSubmitTime: nil
                ),
                1
            ),
            .init(
                "image and image",
                StagedCapture(
                    images: [makeImage(addedAt: 10), makeImage(addedAt: 20)],
                    audios: [],
                    observationContexts: [],
                    lastSubmitTime: nil
                ),
                2
            )
        ]

        for scenario in scenarios {
            #expect(
                scenario.capture.totalItemCount == scenario.expectedCount,
                "\(scenario.name) must count every staged item"
            )
            #expect(
                scenario.capture.submissionMediaTimeline.count == scenario.expectedCount,
                "\(scenario.name) must produce the expected submission timeline size"
            )
            #expect(
                scenario.capture.availableSlots(limit: stagedCaptureCapacity) == stagedCaptureCapacity - scenario.expectedCount,
                "\(scenario.name) must respect the shared two-item capacity"
            )
        }
    }
}
