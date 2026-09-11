import Foundation
import Testing

@Suite("Haptic architecture")
struct HapticArchitectureTests {
    @Test("Facade, value policy, and hardware effects have focused owners")
    func declarationsHaveFocusedOwners() throws {
        let manager = try source(Self.managerPath)
        let models = try source(Self.modelsPath)
        let policy = try source(Self.policyPath)
        let controller = try source(Self.controllerPath)
        let audioSession = try source(Self.audioSessionPath)

        for relocatedToken in [
            "UIImpactFeedbackGenerator",
            "UISelectionFeedbackGenerator",
            "UINotificationFeedbackGenerator",
            "CHHapticEngine",
            "AVAudioSession.sharedInstance()",
            "struct HapticAttemptRecord",
            "enum HapticAttemptOutcome",
            "struct HapticDiagnosticSnapshot",
            "struct HapticCoreProfile"
        ] {
            #expect(!manager.contains(relocatedToken))
        }

        for boundary in [
            "let controller: HapticFeedbackController",
            "HapticFeedbackPolicy.isFeedbackEnabled(",
            "dependencies.controller.triggerImpact(",
            "dependencies.controller.triggerSelection(",
            "dependencies.controller.triggerNotification("
        ] {
            #expect(manager.contains(boundary))
        }

        #expect(models.contains("struct HapticAttemptRecord"))
        #expect(models.contains("struct HapticDiagnosticSnapshot"))
        #expect(policy.contains("enum HapticFeedbackPolicy"))
        #expect(controller.contains("final class HapticFeedbackController"))
        #expect(controller.contains("private var coreHapticsEngine: CoreEngine?"))
        #expect(controller.contains("let prepare: @MainActor () -> Void"))
        #expect(
            controller.contains(
                "let makeCoreEngine: @MainActor () throws -> CoreEngine"
            )
        )
        #expect(audioSession.contains("AVAudioSession.sharedInstance()"))
        #expect(
            audioSession.contains(
                "let prepareForFeedback: @MainActor (HapticEvent) -> Void"
            )
        )
        #expect(
            audioSession.contains(
                "setAllowHapticsAndSystemSoundsDuringRecording(true)"
            )
        )
    }

    @Test("Deterministic layers remain platform-neutral and effect-free")
    func deterministicLayersRemainFocused() throws {
        for path in [Self.modelsPath, Self.policyPath] {
            let contents = try source(path)
            for forbidden in [
                "import AVFoundation",
                "import CoreHaptics",
                "import SwiftUI",
                "import UIKit",
                ".shared",
                "Task {",
                "MerianNetworkClient",
                "SupabaseManager",
                "ModelContext",
                "SwiftData",
                "URLSession"
            ] {
                #expect(!contents.contains(forbidden))
            }
        }

        let manager = try source(Self.managerPath)
        #expect(!manager.contains("import AVFoundation"))
        #expect(!manager.contains("import CoreHaptics"))
        #expect(!manager.contains("import SwiftUI"))
        #expect(!manager.contains("import UIKit"))

        let controller = try source(Self.controllerPath)
        #expect(!controller.contains("import AVFoundation"))
        #expect(!controller.contains("AVAudioSession.sharedInstance()"))

        let audioSession = try source(Self.audioSessionPath)
        #expect(audioSession.contains("import AVFoundation"))
        #expect(!audioSession.contains("import CoreHaptics"))
        #expect(!audioSession.contains("import UIKit"))
    }

    @Test("Haptic owners stay below focused line ceilings")
    func ownersRemainFocusedAndBounded() throws {
        #expect(lineCount(try source(Self.managerPath)) <= 300)
        #expect(lineCount(try source(Self.modelsPath)) <= 125)
        #expect(lineCount(try source(Self.policyPath)) <= 100)
        #expect(lineCount(try source(Self.controllerPath)) <= 400)
        #expect(lineCount(try source(Self.audioSessionPath)) <= 100)
    }

    @Test("Capture-button policy tests remain with their feature owner")
    func captureButtonTestsAreRehomed() throws {
        let managerTests = try source(Self.managerTestsPath)
        let captureTests = try source(Self.captureButtonTestsPath)

        #expect(!managerTests.contains("CaptureButtonHapticFeedback"))
        #expect(captureTests.contains("final class CaptureControlHapticPolicyTests"))
        #expect(captureTests.contains("func testAudioStatesRouteToMediumPulse()"))
        #expect(captureTests.contains("func testDescribeRequiresActiveInput()"))
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
        "apps/ios/Merian/Core/Hardware/HapticManager.swift"
    private static let modelsPath =
        "apps/ios/Merian/Core/Hardware/Haptics/Models/" +
        "HapticFeedbackModels.swift"
    private static let policyPath =
        "apps/ios/Merian/Core/Hardware/Haptics/Policies/" +
        "HapticFeedbackPolicy.swift"
    private static let controllerPath =
        "apps/ios/Merian/Core/Hardware/Haptics/Services/" +
        "HapticFeedbackController.swift"
    private static let audioSessionPath =
        "apps/ios/Merian/Core/Hardware/Haptics/Services/" +
        "HapticAudioSessionAdapter.swift"
    private static let managerTestsPath =
        "apps/ios/MerianTests/Core/Hardware/HapticManagerTests.swift"
    private static let captureButtonTestsPath =
        "apps/ios/MerianTests/Features/Capture/Shared/" +
        "CaptureControlHapticPolicyTests.swift"
}
