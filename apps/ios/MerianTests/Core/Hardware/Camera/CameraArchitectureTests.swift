import Foundation
import Testing

@Suite("Camera Foundation Architecture")
struct CameraArchitectureTests {
    @Test func declarationsHaveFocusedOwners() throws {
        let sources = try swiftSources(below: "apps/ios/Merian")

        for declaration in Self.declarationOwners {
            let owners = sources.compactMap { source in
                source.contents.contains(declaration.signature)
                    ? source.relativePath
                    : nil
            }.sorted()

            #expect(
                owners == [declaration.owner],
                "\(declaration.name) must have one focused owner"
            )
        }

        let manager = try source(Self.managerPath)
        for declaration in Self.relocatedDeclarations {
            #expect(
                !manager.contains(declaration),
                "CameraManager.swift reclaimed \(declaration)"
            )
        }
    }

    @Test func extractedOwnersStayBoundedAndDependencyFocused() throws {
        for owner in Self.extractedOwners {
            let contents = try source(owner.path)
            #expect(
                lineCount(of: contents) <= owner.lineCeiling,
                "\(owner.path) exceeds its \(owner.lineCeiling)-line ceiling"
            )
            #expect(
                imports(in: contents) == owner.imports,
                "\(owner.path) has an unexpected framework dependency"
            )
        }

        let models = try source(Self.modelsPath)
        let policy = try source(Self.policyPath)
        let sessionPolicy = try source(Self.sessionPolicyPath)
        let debouncer = try source(Self.debouncerPath)
        let photoCoordinator = try source(Self.photoCoordinatorPath)
        let videoCoordinator = try source(Self.videoCoordinatorPath)
        let sessionController = try source(Self.sessionControllerPath)
        let videoService = try source(Self.videoServicePath)

        for contents in [models, policy, sessionPolicy, debouncer, photoCoordinator, videoCoordinator] {
            for forbidden in [
                "AVCapture",
                ".shared",
                "MerianNetworkClient",
                "SupabaseManager",
                "URLSession",
                "ModelContext",
                "SwiftData",
                "SwiftUI",
                "UIKit"
            ] {
                #expect(!contents.contains(forbidden))
            }
        }

        for contents in [models, policy, sessionPolicy] {
            #expect(!contents.contains("Task {"))
            #expect(!contents.contains("OSAllocatedUnfairLock"))
            #expect(!contents.contains("NSLock"))
        }

        #expect(!debouncer.contains("AVFoundation"))
        #expect(!debouncer.contains("CameraManager"))
        #expect(photoCoordinator.contains("OSAllocatedUnfairLock(initialState: State())"))
        #expect(photoCoordinator.contains("case reserved(isCancelled: Bool)"))
        #expect(!photoCoordinator.contains("@MainActor"))
        #expect(videoCoordinator.contains("private struct ActiveRequest"))
        #expect(videoCoordinator.contains("private struct ScheduledTask"))
        #expect(videoCoordinator.contains("private final class CompletionContinuationBox: Sendable"))
        #expect(videoCoordinator.contains("defer { continuation = nil }"))
        #expect(videoCoordinator.contains("OSAllocatedUnfairLock(initialState: State())"))
        let videoCoordinatorCode = sourceWithoutLineComments(videoCoordinator)
        #expect(!videoCoordinatorCode.contains("AVFoundation"))
        #expect(!videoCoordinatorCode.contains("CameraManager"))

        for forbidden in [
            "MerianNetworkClient",
            "SupabaseManager",
            "URLSession",
            "ModelContext",
            "SwiftData",
            "SwiftUI",
            "UIKit",
            "HardwareOrchestrator",
            "ViewfinderIntelligence"
        ] {
            #expect(!sessionController.contains(forbidden))
        }
        #expect(sessionController.contains("final class CameraSessionController: @unchecked Sendable"))
        #expect(sessionController.contains("private final class CameraCaptureStack: @unchecked Sendable"))
        #expect(sessionController.contains("dispatchPrecondition(condition: .onQueue(queue))"))
        #expect(sessionController.contains("OSAllocatedUnfairLock(initialState: State())"))
        #expect(sessionController.contains("captureStack.existingSession?.inputs"))
        #expect(sessionController.contains("captureStack.existingDepthOutput"))
        #expect(!sessionController.contains("@Observable"))

        for forbidden in [
            "MerianNetworkClient",
            "SupabaseManager",
            "URLSession",
            "ModelContext",
            "SwiftData",
            "SwiftUI",
            "UIKit"
        ] {
            #expect(!videoService.contains(forbidden))
        }
        #expect(videoService.contains("AVCaptureFileOutputRecordingDelegate"))
        #expect(videoService.contains("@unchecked Sendable"))
        #expect(videoService.contains("private let sessionProvider: SessionProvider"))
        #expect(videoService.contains("private let makeMovieOutput: MovieOutputFactory"))
        #expect(videoService.contains("@MainActor private var preparationTask"))
        #expect(videoService.contains("dispatchPrecondition(condition: .onQueue(queue))"))
        #expect(videoService.contains("private let coordinator: CameraVideoRecordingCoordinator"))
        #expect(!videoService.contains("@Observable"))
    }

    @Test func liveAVFoundationAndRequestOwnersStaySeparated() throws {
        let manager = try source(Self.managerPath)
        let sessionController = try source(Self.sessionControllerPath)
        let videoService = try source(Self.videoServicePath)

        #expect(lineCount(of: manager) <= 600)
        for declaration in [
            "AVCaptureVideoDataOutputSampleBufferDelegate",
            "AVCaptureDepthDataOutputDelegate",
            "AVCapturePhotoCaptureDelegate",
            "didFinishProcessingPhoto photo: AVCapturePhoto"
        ] {
            #expect(
                manager.contains(declaration),
                "Frame, depth, and photo delegate state must remain in CameraManager"
            )
        }

        for declaration in [
            "private final class CameraCaptureStack",
            "final class CameraSessionController: @unchecked Sendable",
            "AVCaptureDevice.DiscoverySession(",
            "session.beginConfiguration()",
            "session.startRunning()",
            "device.lockForConfiguration()",
            "photoOutput.capturePhoto("
        ] {
            #expect(
                sessionController.contains(declaration),
                "Session and active-device AVFoundation state must remain in CameraSessionController"
            )
            #expect(!manager.contains(declaration))
        }

        for declaration in [
            "private lazy var movieOutput = makeMovieOutput()",
            "movieOutput.startRecording(",
            "movieOutput.stopRecording()",
            "didStartRecordingTo fileURL: URL",
            "didFinishRecordingTo outputFileURL: URL"
        ] {
            #expect(
                videoService.contains(declaration),
                "Movie-output AVFoundation state must remain in CameraVideoRecordingService"
            )
            #expect(!manager.contains(declaration))
        }

        for boundary in [
            "private let sessionController: CameraSessionController",
            "OSAllocatedUnfairLock(initialState: AnalysisState())",
            "private let photoCaptureCoordinator = CameraPhotoCaptureCoordinator()",
            "private let videoRecordingService: CameraVideoRecordingService"
        ] {
            #expect(manager.contains(boundary))
        }

        #expect(!manager.contains("AVCaptureFileOutputRecordingDelegate"))
        #expect(!manager.contains("private let videoRecordingCoordinator"))
        #expect(manager.contains("sessionProvider: { sessionController.session }"))
        #expect(manager.contains("queue: sessionController.queue"))
        #expect(videoService.contains("sessionProvider: @escaping SessionProvider"))
        #expect(videoService.contains("queue: DispatchQueue"))
        #expect(videoService.contains("coordinator: CameraVideoRecordingCoordinator"))

        for relocatedRequestState in [
            "private struct CaptureRequest",
            "private let requestsLock = OSAllocatedUnfairLock()",
            "activeCaptureRequests",
            "private struct CameraVideoRecordingScheduledTask",
            "private struct ActiveCameraVideoRecording",
            "private struct CameraVideoRecordingCompletion",
            "private struct CameraVideoRecordingStartContext",
            "private struct CameraVideoRecordingStartHandler",
            "private let videoRecordingLock = OSAllocatedUnfairLock()",
            "private var activeVideoRecording"
        ] {
            #expect(!manager.contains(relocatedRequestState))
        }
    }

    @Test func focusedSuitesRetainCameraCoverage() throws {
        let manager = try source(Self.managerPath)
        let sessionController = try source(Self.sessionControllerPath)
        let tests = try source(Self.behaviorTestsPath)
        let photoTests = try source(Self.photoCoordinatorTestsPath)
        let videoTests = try source(Self.videoCoordinatorTestsPath)
        let sessionTests = try source(Self.sessionPolicyTestsPath)
        let sessionControllerTests = try source(Self.sessionControllerTestsPath)

        #expect(tests.contains("final class CameraManagerTests: XCTestCase"))
        for testName in Self.requiredBehaviorTests {
            #expect(
                tests.contains("func \(testName)("),
                "CameraManagerTests is missing \(testName)"
            )
        }

        #expect(photoTests.contains("struct CameraPhotoCaptureCoordinatorTests"))
        for testName in Self.requiredPhotoCoordinatorTests {
            #expect(
                photoTests.contains("func \(testName)("),
                "CameraPhotoCaptureCoordinatorTests is missing \(testName)"
            )
        }

        #expect(videoTests.contains("struct CameraVideoRecordingCoordinatorTests"))
        for testName in Self.requiredVideoCoordinatorTests {
            #expect(
                videoTests.contains("func \(testName)("),
                "CameraVideoRecordingCoordinatorTests is missing \(testName)"
            )
        }

        #expect(sessionTests.contains("final class CameraSessionPolicyTests: XCTestCase"))
        for testName in Self.requiredSessionPolicyTests {
            #expect(
                sessionTests.contains("func \(testName)("),
                "CameraSessionPolicyTests is missing \(testName)"
            )
        }

        #expect(
            sessionControllerTests.contains(
                "final class CameraSessionControllerTests: XCTestCase"
            )
        )
        #expect(
            sessionControllerTests.contains(
                "func testConstructionDefersCaptureObjectCreation("
            )
        )
        #expect(
            sessionControllerTests.contains(
                "func testConcurrentSessionAccessCreatesOneRootSession("
            )
        )
        #expect(
            sessionControllerTests.contains(
                "func testNoOpControlsAndStopsDoNotResolveCaptureStack("
            )
        )
        #expect(
            sessionControllerTests.contains(
                "func testFailedInitialConfigurationDoesNotBlockRetry("
            )
        )
        #expect(
            sessionController.contains(
                "guard self?.ownsSessionLifecycle("
            )
        )
        #expect(
            sessionController.components(
                separatedBy: "invalidateSessionLifecycle()"
            ).count == 4
        )
        #expect(manager.contains("sessionPresentationState.register("))
        #expect(
            sessionTests.contains(
                "func testPresentationGenerationCoalescesDuplicateLifecycleIntents("
            )
        )
    }

    private func source(_ path: String) throws -> String {
        let file = try repositoryRoot().appendingPathComponent(path)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private func swiftSources(
        below path: String
    ) throws -> [(relativePath: String, contents: String)] {
        let root = try repositoryRoot()
        let directory = root.appendingPathComponent(path)
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )
        var sources: [(relativePath: String, contents: String)] = []

        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let relativePath = String(file.path.dropFirst(root.path.count + 1))
            sources.append((
                relativePath,
                try String(contentsOf: file, encoding: .utf8)
            ))
        }

        return sources
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()

        for _ in 0..<12 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        throw CocoaError(.fileNoSuchFile)
    }

    private func lineCount(of source: String) -> Int {
        source.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private func imports(in source: String) -> Set<String> {
        Set(source.split(separator: "\n").compactMap { line in
            let value = line.trimmingCharacters(in: .whitespaces)
            return value.contains("import ") ? value : nil
        })
    }

    private func sourceWithoutLineComments(_ source: String) -> String {
        source.split(separator: "\n").compactMap { line in
            let value = line.trimmingCharacters(in: .whitespaces)
            return value.hasPrefix("//") ? nil : value
        }.joined(separator: "\n")
    }

    private static let managerPath =
        "apps/ios/Merian/Core/Hardware/CameraManager.swift"
    private static let modelsPath =
        "apps/ios/Merian/Core/Hardware/Camera/Models/CameraVideoRecordingModels.swift"
    private static let policyPath =
        "apps/ios/Merian/Core/Hardware/Camera/Policies/CameraVideoRecordingPolicy.swift"
    private static let sessionPolicyPath =
        "apps/ios/Merian/Core/Hardware/Camera/Policies/CameraSessionPolicy.swift"
    private static let debouncerPath =
        "apps/ios/Merian/Core/Hardware/Camera/Coordination/CameraTargetFPSDebouncer.swift"
    private static let photoCoordinatorPath =
        "apps/ios/Merian/Core/Hardware/Camera/Coordination/CameraPhotoCaptureCoordinator.swift"
    private static let videoCoordinatorPath =
        "apps/ios/Merian/Core/Hardware/Camera/Coordination/CameraVideoRecordingCoordinator.swift"
    private static let sessionControllerPath =
        "apps/ios/Merian/Core/Hardware/Camera/Services/CameraSessionController.swift"
    private static let videoServicePath =
        "apps/ios/Merian/Core/Hardware/Camera/Services/CameraVideoRecordingService.swift"
    private static let behaviorTestsPath =
        "apps/ios/MerianTests/Core/Hardware/CameraManagerTests.swift"
    private static let photoCoordinatorTestsPath =
        "apps/ios/MerianTests/Core/Hardware/Camera/CameraPhotoCaptureCoordinatorTests.swift"
    private static let videoCoordinatorTestsPath =
        "apps/ios/MerianTests/Core/Hardware/Camera/CameraVideoRecordingCoordinatorTests.swift"
    private static let sessionPolicyTestsPath =
        "apps/ios/MerianTests/Core/Hardware/Camera/CameraSessionPolicyTests.swift"
    private static let sessionControllerTestsPath =
        "apps/ios/MerianTests/Core/Hardware/Camera/CameraSessionControllerTests.swift"

    private static let declarationOwners = [
        (
            name: "CameraVideoRecording",
            signature: "struct CameraVideoRecording: Sendable",
            owner: modelsPath
        ),
        (
            name: "CameraVideoRecordingGeneration",
            signature: "struct CameraVideoRecordingGeneration: Equatable, Sendable",
            owner: modelsPath
        ),
        (
            name: "CameraVideoRecordingScheduledAction",
            signature: "struct CameraVideoRecordingScheduledAction: Equatable, Sendable",
            owner: modelsPath
        ),
        (
            name: "CameraVideoAudioPermissionPolicy",
            signature: "enum CameraVideoAudioPermissionPolicy",
            owner: policyPath
        ),
        (
            name: "CameraVideoRecordingGenerationGate",
            signature: "struct CameraVideoRecordingGenerationGate: Sendable",
            owner: policyPath
        ),
        (
            name: "CameraZoomConfiguration",
            signature: "struct CameraZoomConfiguration: Equatable, Sendable",
            owner: sessionPolicyPath
        ),
        (
            name: "CameraSessionPolicy",
            signature: "enum CameraSessionPolicy",
            owner: sessionPolicyPath
        ),
        (
            name: "CameraTargetFPSDebouncer",
            signature: "final class CameraTargetFPSDebouncer",
            owner: debouncerPath
        ),
        (
            name: "CameraPhotoCaptureCoordinator",
            signature: "final class CameraPhotoCaptureCoordinator: Sendable",
            owner: photoCoordinatorPath
        ),
        (
            name: "CameraVideoRecordingCoordinator",
            signature: "final class CameraVideoRecordingCoordinator: Sendable",
            owner: videoCoordinatorPath
        ),
        (
            name: "CameraSessionController",
            signature: "final class CameraSessionController: @unchecked Sendable",
            owner: sessionControllerPath
        ),
        (
            name: "CameraVideoRecordingService",
            signature: "final class CameraVideoRecordingService:",
            owner: videoServicePath
        ),
        (
            name: "CameraManager",
            signature: "@Observable final class CameraManager",
            owner: managerPath
        )
    ]

    private static let relocatedDeclarations = [
        "struct CameraVideoRecording: Sendable",
        "enum CameraVideoAudioPermissionPolicy",
        "struct CameraVideoRecordingGeneration: Equatable, Sendable",
        "struct CameraVideoRecordingScheduledAction: Equatable, Sendable",
        "struct CameraVideoRecordingGenerationGate: Sendable",
        "struct CameraZoomConfiguration: Equatable, Sendable",
        "enum CameraSessionPolicy",
        "final class CameraTargetFPSDebouncer",
        "final class CameraPhotoCaptureCoordinator: Sendable",
        "final class CameraVideoRecordingCoordinator: Sendable",
        "final class CameraSessionController: @unchecked Sendable",
        "final class CameraVideoRecordingService:"
    ]

    private static let extractedOwners = [
        (
            path: modelsPath,
            lineCeiling: 100,
            imports: Set(["import Foundation"])
        ),
        (
            path: policyPath,
            lineCeiling: 100,
            imports: Set([
                "@preconcurrency import AVFoundation",
                "import Foundation"
            ])
        ),
        (
            path: sessionPolicyPath,
            lineCeiling: 100,
            imports: Set([
                "@preconcurrency import AVFoundation",
                "import Foundation"
            ])
        ),
        (
            path: debouncerPath,
            lineCeiling: 100,
            imports: Set(["import Foundation"])
        ),
        (
            path: photoCoordinatorPath,
            lineCeiling: 220,
            imports: Set([
                "import Foundation",
                "import os"
            ])
        ),
        (
            path: videoCoordinatorPath,
            lineCeiling: 380,
            imports: Set([
                "import Foundation",
                "import os"
            ])
        ),
        (
            path: sessionControllerPath,
            lineCeiling: 600,
            imports: Set([
                "@preconcurrency import AVFoundation",
                "import Foundation",
                "import os"
            ])
        ),
        (
            path: videoServicePath,
            lineCeiling: 600,
            imports: Set([
                "@preconcurrency import AVFoundation",
                "import Foundation",
                "import os"
            ])
        )
    ]

    private static let requiredBehaviorTests = [
        "testVideoAudioOnlyUsesPreviouslyGrantedMicrophoneAccess",
        "testVideoRecordingServiceDefersCaptureObjectCreation",
        "testTargetFPSDebouncerReadsCurrentTargetAfterDelay",
        "testTargetFPSDebouncerRejectsReplacedGeneration",
        "testVideoRecordingGenerationBindsCallbacksToExpectedURL",
        "testVideoRecordingGenerationRejectsABAActions",
        "testVideoRecordingGenerationRejectsCooperativelyCancelledReplacedTasks"
    ]

    private static let requiredPhotoCoordinatorTests = [
        "cancellationBeforeRegistrationResumesAndClearsReservation",
        "completionClaimsRequestExactlyOnce",
        "cancellationClaimsActiveRequestExactlyOnce",
        "cancellationAndCompletionRaceHasExactlyOneWinner",
        "timeoutResumesWithExistingCameraErrorContract",
        "identifierCanBeReservedAgainAfterTerminalResolution"
    ]

    private static let requiredVideoCoordinatorTests = [
        "installAndCompletionExposeOnlyTheActiveGeneration",
        "startClaimRequiresTheExactCallbackAndIsOneShot",
        "replacementActionsRejectStaleTimeoutAndStopWork",
        "replacedTaskDoesNotFireWhenSleepIgnoresCancellation",
        "callbackCompletionRejectsTheWrongURLAndClearsState",
        "cancellationAndDelegateCompletionRaceHasOneWinner"
    ]

    private static let requiredSessionPolicyTests = [
        "testZoomConfigurationCapsRangeAndFiltersOpticalStops",
        "testZoomClampingKeepsUIAndHardwareBoundsIndependent",
        "testFrameDurationClampsToSupportedRange",
        "testFrameDurationUpdateOrderProtectsDeviceConstraints"
    ]
}
