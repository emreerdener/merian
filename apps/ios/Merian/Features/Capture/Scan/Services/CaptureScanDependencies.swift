import CoreGraphics
import CoreLocation
import Foundation

struct CaptureScanCameraDependencies {
    let setFocusPoint: @MainActor @Sendable (CGPoint) -> Void
    let captureImage: @MainActor @Sendable () async throws -> Data
    let recordVideo: @MainActor @Sendable (
        _ maxDuration: TimeInterval,
        _ onStarted: (@MainActor @Sendable () -> Void)?
    ) async throws -> CameraVideoRecording
    let stopVideoRecording: @MainActor @Sendable () -> Void
    let cancelVideoRecording: @MainActor @Sendable () -> Void
}

struct CaptureScanContextDependencies {
    let requestCurrentLocation: @MainActor @Sendable () async -> CLLocation?
    let lastKnownLocation: @MainActor @Sendable () -> CLLocation?
    let fetchDeferredContext: @MainActor @Sendable (
        _ lockedLocation: CLLocation?
    ) async -> EnvironmentContext
}

struct CaptureScanLibraryDependencies {
    let saveImage: @MainActor @Sendable (
        _ imageData: Data,
        _ location: CLLocation?
    ) async -> Void
    let saveVideo: @MainActor @Sendable (
        _ fileURL: URL,
        _ location: CLLocation?
    ) async -> Void
}

struct CaptureScanMediaDependencies {
    let prepareStill: @Sendable (
        CaptureScanStillPreparationRequest
    ) async throws -> PreparedCaptureScanStill?
    let prepareVideo: @Sendable (
        CaptureScanVideoPreparationRequest
    ) async throws -> PreparedCaptureScanVideo
}

struct CaptureScanFeedbackDependencies {
    let selection: @MainActor @Sendable () -> Void
    let zoomOpticalStop: @MainActor @Sendable () -> Void
    let zoomTick: @MainActor @Sendable () -> Void
    let photoCapture: @MainActor @Sendable () -> Void
    let videoStarted: @MainActor @Sendable () -> Void
    let videoCompleted: @MainActor @Sendable () -> Void
    let success: @MainActor @Sendable () -> Void
    let error: @MainActor @Sendable () -> Void
}

struct CaptureScanDependencies {
    let camera: CaptureScanCameraDependencies
    let context: CaptureScanContextDependencies
    let library: CaptureScanLibraryDependencies
    let media: CaptureScanMediaDependencies
    let canStartProScan: @MainActor @Sendable () -> Bool
    let feedback: CaptureScanFeedbackDependencies

    @MainActor
    static func live(diContainer: AppDIContainer) -> Self {
        Self(
            camera: CaptureScanCameraDependencies(
                setFocusPoint: { point in
                    diContainer.cameraManager.setFocusPoint(point)
                },
                captureImage: {
                    try await diContainer.cameraManager.captureImage()
                },
                recordVideo: { maxDuration, onStarted in
                    try await diContainer.cameraManager.recordVideo(
                        maxDuration: maxDuration,
                        onStarted: onStarted
                    )
                },
                stopVideoRecording: {
                    diContainer.cameraManager.stopVideoRecording()
                },
                cancelVideoRecording: {
                    diContainer.cameraManager.cancelVideoRecording()
                }
            ),
            context: CaptureScanContextDependencies(
                requestCurrentLocation: {
                    await diContainer.environmentContextManager
                        .requestCurrentLocation()
                },
                lastKnownLocation: {
                    diContainer.environmentContextManager.lastKnownLocation
                },
                fetchDeferredContext: { lockedLocation in
                    await diContainer.environmentContextManager
                        .fetchDeferredContext(
                            preLockedLocation: lockedLocation
                        )
                }
            ),
            library: CaptureScanLibraryDependencies(
                saveImage: { imageData, location in
                    await diContainer.photoLibraryManager.saveImageToLibrary(
                        imageData: imageData,
                        location: location
                    )
                },
                saveVideo: { fileURL, location in
                    await diContainer.photoLibraryManager.saveVideoToLibrary(
                        fileURL: fileURL,
                        location: location
                    )
                }
            ),
            media: CaptureScanMediaDependencies(
                prepareStill: { request in
                    try await CaptureScanStillMediaPreparer.prepare(request)
                },
                prepareVideo: { request in
                    try await CaptureScanVideoMediaPreparer.prepare(request)
                }
            ),
            canStartProScan: {
                diContainer.revenueCatManager.canStartProScan
            },
            feedback: CaptureScanFeedbackDependencies(
                selection: {
                    diContainer.hapticManager.triggerSelectionPulse()
                },
                zoomOpticalStop: {
                    diContainer.hapticManager.triggerHeavyImpact(
                        intensity: 1.0
                    )
                },
                zoomTick: {
                    diContainer.hapticManager.triggerLightImpact(
                        intensity: 0.4
                    )
                },
                photoCapture: {
                    diContainer.hapticManager.triggerHeavyImpact(
                        intensity: 1.0,
                        source: "capture.photo.hardware"
                    )
                },
                videoStarted: {
                    diContainer.hapticManager.triggerHeavyImpact(
                        intensity: 1.0,
                        source: CaptureButtonHapticSource.videoStart.rawValue
                    )
                },
                videoCompleted: {
                    diContainer.hapticManager.triggerHeavyImpact(
                        intensity: 1.0,
                        source: "capture.video.completed"
                    )
                },
                success: {
                    diContainer.hapticManager.triggerSuccessPulse()
                },
                error: {
                    diContainer.hapticManager.triggerErrorThump()
                }
            )
        )
    }
}
