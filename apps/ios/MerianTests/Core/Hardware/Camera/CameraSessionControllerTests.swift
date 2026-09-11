import AVFoundation
@testable import Merian
import os
import XCTest

final class CameraSessionControllerTests: XCTestCase {
    func testConstructionDefersCaptureObjectCreation() {
        let creationCounts = OSAllocatedUnfairLock(
            initialState: (sessions: 0, videos: 0, depths: 0, photos: 0)
        )
        let controller = CameraSessionController(
            queue: DispatchQueue(label: "CameraSessionControllerTests.deferred"),
            makeSession: {
                creationCounts.withLock { $0.sessions += 1 }
                return AVCaptureSession()
            },
            makeVideoOutput: {
                creationCounts.withLock { $0.videos += 1 }
                return AVCaptureVideoDataOutput()
            },
            makeDepthOutput: {
                creationCounts.withLock { $0.depths += 1 }
                return AVCaptureDepthDataOutput()
            },
            makePhotoOutput: {
                creationCounts.withLock { $0.photos += 1 }
                return AVCapturePhotoOutput()
            }
        )

        withExtendedLifetime(controller) {
            let counts = creationCounts.withLock { $0 }
            XCTAssertEqual(counts.sessions, 0)
            XCTAssertEqual(counts.videos, 0)
            XCTAssertEqual(counts.depths, 0)
            XCTAssertEqual(counts.photos, 0)
        }
    }

    func testConcurrentSessionAccessCreatesOneRootSession() {
        let sessionCreations = OSAllocatedUnfairLock(initialState: 0)
        let controller = CameraSessionController(
            queue: DispatchQueue(label: "CameraSessionControllerTests.concurrent"),
            makeSession: {
                sessionCreations.withLock { $0 += 1 }
                return AVCaptureSession()
            }
        )

        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            _ = controller.session
        }

        XCTAssertEqual(sessionCreations.withLock { $0 }, 1)
    }

    func testNoOpControlsAndStopsDoNotResolveCaptureStack() async {
        let creationCounts = OSAllocatedUnfairLock(
            initialState: (sessions: 0, videos: 0, depths: 0, photos: 0)
        )
        let controller = CameraSessionController(
            queue: DispatchQueue(label: "CameraSessionControllerTests.noOp"),
            makeSession: {
                creationCounts.withLock { $0.sessions += 1 }
                return AVCaptureSession()
            },
            makeVideoOutput: {
                creationCounts.withLock { $0.videos += 1 }
                return AVCaptureVideoDataOutput()
            },
            makeDepthOutput: {
                creationCounts.withLock { $0.depths += 1 }
                return AVCaptureDepthDataOutput()
            },
            makePhotoOutput: {
                creationCounts.withLock { $0.photos += 1 }
                return AVCapturePhotoOutput()
            }
        )

        controller.applyTargetFPS(30)
        controller.applyIdleFrameRate()
        controller.toggleTorch { _ in }
        controller.applyZoom(
            requestedFactor: 2,
            maximumFactor: 5,
            ramp: false,
            onChanged: { _ in }
        )
        controller.setFocusPoint(.zero)
        controller.resetFocusAndExposure()
        await withCheckedContinuation { continuation in
            controller.stopSession {
                continuation.resume()
            }
        }
        await controller.stopSessionAndWait()

        let counts = creationCounts.withLock { $0 }
        XCTAssertEqual(counts.sessions, 0)
        XCTAssertEqual(counts.videos, 0)
        XCTAssertEqual(counts.depths, 0)
        XCTAssertEqual(counts.photos, 0)
    }

    func testFailedInitialConfigurationDoesNotBlockRetry()
        async {
        let inputRequests = OSAllocatedUnfairLock(initialState: 0)
        let delegate = CameraSessionDelegateProbe()
        let controller = CameraSessionController(
            queue: DispatchQueue(
                label: "CameraSessionControllerTests.configurationRetry"
            ),
            makeVideoInput: {
                inputRequests.withLock { $0 += 1 }
                return nil
            }
        )
        let starts = OSAllocatedUnfairLock(initialState: 0)

        for _ in 0..<2 {
            controller.startSession(
                videoDelegate: delegate,
                depthDelegate: delegate,
                prepareVideoOutput: { _ in },
                onStarted: { _ in starts.withLock { $0 += 1 } }
            )
            await controller.stopSessionAndWait()
        }

        XCTAssertEqual(inputRequests.withLock { $0 }, 2)
        XCTAssertEqual(starts.withLock { $0 }, 0)
    }
}

private final class CameraSessionDelegateProbe: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureDepthDataOutputDelegate {
    func captureOutput(
        _: AVCaptureOutput,
        didOutput _: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {}

    func depthDataOutput(
        _: AVCaptureDepthDataOutput,
        didOutput _: AVDepthData,
        timestamp _: CMTime,
        connection _: AVCaptureConnection
    ) {}
}
