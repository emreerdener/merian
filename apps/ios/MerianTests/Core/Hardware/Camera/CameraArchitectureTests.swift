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
        let debouncer = try source(Self.debouncerPath)

        for contents in [models, policy, debouncer] {
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

        for contents in [models, policy] {
            #expect(!contents.contains("Task {"))
            #expect(!contents.contains("OSAllocatedUnfairLock"))
            #expect(!contents.contains("NSLock"))
        }

        #expect(!debouncer.contains("AVFoundation"))
        #expect(!debouncer.contains("CameraManager"))
    }

    @Test func liveCaptureAndRecordingStateRemainColocated() throws {
        let manager = try source(Self.managerPath)

        #expect(lineCount(of: manager) <= 1_650)
        for declaration in [
            "private final class CameraCaptureStack",
            "private struct CameraVideoRecordingScheduledTask",
            "private struct ActiveCameraVideoRecording",
            "private struct CameraVideoRecordingCompletion",
            "private struct CameraVideoRecordingStartContext",
            "private struct CameraVideoRecordingStartHandler"
        ] {
            #expect(
                manager.contains(declaration),
                "Live AVFoundation state must remain co-located with CameraManager"
            )
        }

        for boundary in [
            "private let captureStack = CameraCaptureStack()",
            "private let queue = DispatchQueue(label: \"com.merian.camera\")",
            "let stateLock = OSAllocatedUnfairLock()",
            "private let requestsLock = OSAllocatedUnfairLock()",
            "private let videoRecordingLock = OSAllocatedUnfairLock()"
        ] {
            #expect(manager.contains(boundary))
        }
    }

    @Test func behavioralSuiteRetainsCameraPolicyCoverage() throws {
        let tests = try source(Self.behaviorTestsPath)

        #expect(tests.contains("final class CameraManagerTests: XCTestCase"))
        for testName in Self.requiredBehaviorTests {
            #expect(
                tests.contains("func \(testName)("),
                "CameraManagerTests is missing \(testName)"
            )
        }
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

    private static let managerPath =
        "apps/ios/Merian/Core/Hardware/CameraManager.swift"
    private static let modelsPath =
        "apps/ios/Merian/Core/Hardware/Camera/Models/CameraVideoRecordingModels.swift"
    private static let policyPath =
        "apps/ios/Merian/Core/Hardware/Camera/Policies/CameraVideoRecordingPolicy.swift"
    private static let debouncerPath =
        "apps/ios/Merian/Core/Hardware/Camera/Coordination/CameraTargetFPSDebouncer.swift"
    private static let behaviorTestsPath =
        "apps/ios/MerianTests/Core/Hardware/CameraManagerTests.swift"

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
            name: "CameraTargetFPSDebouncer",
            signature: "final class CameraTargetFPSDebouncer",
            owner: debouncerPath
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
        "final class CameraTargetFPSDebouncer"
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
            path: debouncerPath,
            lineCeiling: 100,
            imports: Set(["import Foundation"])
        )
    ]

    private static let requiredBehaviorTests = [
        "testVideoAudioOnlyUsesPreviouslyGrantedMicrophoneAccess",
        "testTargetFPSDebouncerReadsCurrentTargetAfterDelay",
        "testTargetFPSDebouncerRejectsReplacedGeneration",
        "testVideoRecordingGenerationBindsCallbacksToExpectedURL",
        "testVideoRecordingGenerationRejectsABAActions",
        "testVideoRecordingGenerationRejectsCooperativelyCancelledReplacedTasks"
    ]
}
