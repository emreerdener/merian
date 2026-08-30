import Foundation
import XCTest

@testable import Merian

final class CaptureRecordArchitectureTests: XCTestCase {
    func testProductionRecordFilesStayBelowSixHundredLines() throws {
        let files = try swiftFiles(in: recordSourceRoot())

        XCTAssertFalse(files.isEmpty)
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let lineCount = contents.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count
            XCTAssertLessThanOrEqual(
                lineCount,
                600,
                "\(file.lastPathComponent) has \(lineCount) lines"
            )
        }
    }

    func testRecordOwnershipDirectoriesRemainPresent() throws {
        let root = try recordSourceRoot()
        for directory in [
            "Models",
            "Services",
            "ViewModels",
            "Views",
            "Components"
        ] {
            var isDirectory: ObjCBool = false
            let path = root.appendingPathComponent(directory).path
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: path,
                    isDirectory: &isDirectory
                ),
                "Capture Record is missing its \(directory) owner"
            )
            XCTAssertTrue(isDirectory.boolValue)
        }
    }

    func testViewsComponentsAndViewModelsDoNotResolveLiveServices() throws {
        let root = try recordSourceRoot()
        let forbiddenTokens = [
            "AppDIContainer.shared",
            "@Environment(AudioCaptureManager.self)",
            "@Environment(AppSettings.self)",
            "HapticManager.shared",
            "MerianNetworkClient.shared",
            "SupabaseManager.shared",
            "RevenueCatManager.shared",
            "UIApplication.shared",
            "UserDefaults.standard",
            "URLSession("
        ]

        for directory in ["Views", "Components", "ViewModels"] {
            for file in try swiftFiles(
                in: root.appendingPathComponent(directory)
            ) {
                let contents = try String(contentsOf: file, encoding: .utf8)
                for token in forbiddenTokens {
                    XCTAssertFalse(
                        contents.contains(token),
                        "\(file.lastPathComponent) directly owns \(token)"
                    )
                }
            }
        }
    }

    func testModelsRemainDeterministicAndPlatformNeutral() throws {
        let root = try recordSourceRoot().appendingPathComponent("Models")
        let forbiddenTokens = [
            "import AVFoundation",
            "import SwiftUI",
            "import UIKit",
            "AudioCaptureManager",
            "HapticManager.shared",
            "UIApplication.shared",
            "UserDefaults.standard"
        ]

        for file in try swiftFiles(in: root) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    contents.contains(token),
                    "\(file.lastPathComponent) contains \(token)"
                )
            }
        }
    }

    func testCrossFeatureComponentsHaveSharedOwners() throws {
        let repository = try repositoryRoot()
        let sharedCountdown = repository.appendingPathComponent(
            "apps/ios/Merian/Features/Capture/Shared/Components/" +
                "RecordingCountdownBadge.swift"
        )
        let sharedRenderer = repository.appendingPathComponent(
            "apps/ios/Merian/Core/Media/AudioSpectrogramRenderer.swift"
        )
        let sharedView = repository.appendingPathComponent(
            "apps/ios/Merian/Core/UI/Components/AudioSpectrogramView.swift"
        )
        let oldRecordRenderer = try recordSourceRoot().appendingPathComponent(
            "Views/SpectrogramView.swift"
        )

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sharedCountdown.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sharedRenderer.path)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedView.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: oldRecordRenderer.path)
        )
    }

    func testLifecycleOwnersFencePendingAudioTransitions() throws {
        let repository = try repositoryRoot()
        let lifecycle = try String(
            contentsOf: repository.appendingPathComponent(
                "apps/ios/Merian/Features/Capture/Shell/ViewModels/" +
                    "CaptureWorkspaceViewModel+Lifecycle.swift"
            ),
            encoding: .utf8
        )
        let controlBar = try String(
            contentsOf: repository.appendingPathComponent(
                "apps/ios/Merian/Core/UI/Components/" +
                    "CaptureControlBar.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            lifecycle.contains(
                "audioCaptureManager.cancelPendingRecordingTransition()"
            )
        )
        XCTAssertTrue(controlBar.contains(".onChange(of: scenePhase)"))
        XCTAssertTrue(
            controlBar.contains(
                "audioCaptureManager.cancelPendingRecordingTransition()"
            )
        )
    }

    private func recordSourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/Capture/Record"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        return root
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()

        for _ in 0..<10 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        throw CocoaError(.fileNoSuchFile)
    }

    private func swiftFiles(in root: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys)
        ) else {
            return []
        }

        return try enumerator.compactMap { element in
            guard let url = element as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: keys).isRegularFile == true
            else {
                return nil
            }
            return url
        }
    }
}
