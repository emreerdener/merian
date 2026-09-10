import Foundation
import Testing

@testable import Merian

@Suite("Audio capture architecture")
struct AudioCaptureArchitectureTests {
    @Test("Recording engine, tap, WAV, and DSP have one focused owner")
    func recordingResourcesHaveOneFocusedOwner() throws {
        let manager = try source(Self.managerPath)
        let controller = try source(Self.recordingControllerPath)

        for relocatedToken in [
            "private var audioEngine: AVAudioEngine?",
            "private let spectrogram = SpectrogramActor()",
            "private var spectrogramContinuation",
            "private var dspTask",
            "private var audioSessionLease",
            "AVAudioFile(",
            "inputNode.installTap(",
            "copyPCMBuffer("
        ] {
            #expect(!manager.contains(relocatedToken))
        }

        for managerBoundary in [
            "private let recordingController: AudioRecordingEngineController",
            "recordingController.start(",
            "recordingController.pause()",
            "recordingController.resume(",
            "recordingController.finishRecording()",
            "recordingController.cancelRecording()",
            "recordingController.resetAnalysis()"
        ] {
            #expect(manager.contains(managerBoundary))
        }

        for controllerBoundary in [
            "private struct ActiveRecording",
            "private let spectrogram = SpectrogramActor()",
            "private var activeRecording: ActiveRecording?",
            "private var pendingOperation: UUID?",
            "bufferingPolicy: .bufferingNewest(2)",
            "AudioRecordingWAVFormatPolicy",
            "inputNode.installTap(",
            "recording.engine.removeTap()",
            "recording.engine.stop()",
            "AudioSessionCoordinator.shared.activate(",
            "nonisolated private static func copyPCMBuffer("
        ] {
            #expect(controller.contains(controllerBoundary))
        }

        let removeTapIndex = try #require(
            controller.range(of: "recording.engine.removeTap()")?.lowerBound
        )
        let stopIndex = try #require(
            controller.range(of: "recording.engine.stop()")?.lowerBound
        )
        #expect(removeTapIndex < stopIndex)

        for forbidden in [
            "import SwiftUI",
            "import UIKit",
            "MerianNetworkClient",
            "SupabaseManager",
            "ModelContext",
            "SwiftData",
            "URLSession"
        ] {
            #expect(!controller.contains(forbidden))
        }
    }

    @Test("Review playback state has one focused owner")
    func reviewPlaybackStateHasOneFocusedOwner() throws {
        let manager = try source(Self.managerPath)
        let controller = try source(Self.playbackControllerPath)

        for relocatedToken in [
            "private var audioPlayer: AVAudioPlayer?",
            "private var playbackProgressTask",
            "private var playbackCompletionTask",
            "AudioSessionCoordinator.shared.activate(.playback)"
        ] {
            #expect(!manager.contains(relocatedToken))
        }

        for managerBoundary in [
            "private let playbackController: AudioReviewPlaybackController",
            "playbackController.start(",
            "playbackController.stop()",
            "playbackController.seek(to:",
            "invalidateRecordingTransitions()\n        stopPlayback()"
        ] {
            #expect(manager.contains(managerBoundary))
        }

        for controllerBoundary in [
            "protocol AudioReviewPlaybackPlayer: AnyObject",
            "private struct ActivePlayback",
            "private var activePlayback: ActivePlayback?",
            "AudioSessionCoordinator.shared.activate(.playback)",
            "let generation = UUID()",
            "guard player.play() else",
            "guard !Task.isCancelled"
        ] {
            #expect(controller.contains(controllerBoundary))
        }

        for forbidden in [
            "import SwiftUI",
            "import UIKit",
            "MerianNetworkClient",
            "SupabaseManager",
            "ModelContext",
            "SwiftData",
            "URLSession"
        ] {
            #expect(!controller.contains(forbidden))
        }
    }

    @Test("Audio capture owners remain focused and bounded")
    func audioCaptureOwnersRemainFocusedAndBounded() throws {
        let manager = try source(Self.managerPath)
        let recordingController = try source(Self.recordingControllerPath)
        let playbackController = try source(Self.playbackControllerPath)
        let recordingModels = try source(Self.recordingModelsPath)
        let wavPolicy = try source(Self.wavPolicyPath)

        #expect(lineCount(manager) <= 600)
        #expect(lineCount(recordingController) <= 550)
        #expect(lineCount(playbackController) <= 250)
        #expect(lineCount(recordingModels) <= 100)
        #expect(lineCount(wavPolicy) <= 100)
    }

    @Test("Recording engine regression suite remains present")
    func recordingEngineRegressionSuiteRemainsPresent() throws {
        let tests = try source(Self.recordingTestsPath)

        for testName in [
            "finishRetainsWAVAndTearsDownEngine",
            "failedStartRemovesTapAndPartialWAV",
            "inputFormatRecoverySucceeds",
            "exhaustedInputRecoveryFailsClosed",
            "cancellationRejectsLateActivationLease",
            "concurrentResumeRequestsCoalesce",
            "failedResumeActivationAllowsRetry",
            "wavOutputUsesCanonicalPCMFormat",
            "invalidHardwareFormatIsRejected"
        ] {
            #expect(tests.contains("func \(testName)("))
        }
    }

    @Test("Playback regression suite remains present")
    func playbackRegressionSuiteRemainsPresent() throws {
        let tests = try source(Self.playbackTestsPath)

        for testName in [
            "stopBeforeActivationRejectsLateLease",
            "failedPlayerStartFinalizesAndReleasesLease",
            "completionWaitFailureFinalizesAndReleasesLease",
            "staleCompletionCannotFinishReplacement",
            "managerPreservesResumeProgressAndClearsCompletionState",
            "managerResetStopsPlaybackAndReleasesLease"
        ] {
            #expect(tests.contains("func \(testName)("))
        }
    }

    private func source(_ path: String) throws -> String {
        let file = try repositoryRoot().appendingPathComponent(path)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private func lineCount(_ source: String) -> Int {
        source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
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

    private static let managerPath =
        "apps/ios/Merian/Core/Hardware/AudioCaptureManager.swift"
    private static let recordingControllerPath =
        "apps/ios/Merian/Core/Hardware/AudioCapture/Services/" +
        "AudioRecordingEngineController.swift"
    private static let playbackControllerPath =
        "apps/ios/Merian/Core/Hardware/AudioCapture/Services/" +
        "AudioReviewPlaybackController.swift"
    private static let recordingModelsPath =
        "apps/ios/Merian/Core/Hardware/AudioCapture/Models/" +
        "AudioRecordingEngineModels.swift"
    private static let wavPolicyPath =
        "apps/ios/Merian/Core/Hardware/AudioCapture/Policies/" +
        "AudioRecordingWAVFormatPolicy.swift"
    private static let recordingTestsPath =
        "apps/ios/MerianTests/Core/Hardware/AudioCapture/" +
        "AudioRecordingEngineControllerTests.swift"
    private static let playbackTestsPath =
        "apps/ios/MerianTests/Core/Hardware/AudioCapture/" +
        "AudioReviewPlaybackControllerTests.swift"
}
