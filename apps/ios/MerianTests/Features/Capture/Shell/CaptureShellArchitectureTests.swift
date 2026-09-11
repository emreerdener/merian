import Foundation
import XCTest

@testable import Merian

final class CaptureShellArchitectureTests: XCTestCase {
    func testProductionShellFilesStayBelowSixHundredLines() throws {
        let files = try swiftFiles(in: shellSourceRoot())

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

    func testShellOwnershipDirectoriesRemainPresent() throws {
        let root = try shellSourceRoot()
        for directory in [
            "Models",
            "Services",
            "ViewModels",
            "Views",
            "Components",
            "Modifiers"
        ] {
            var isDirectory: ObjCBool = false
            let path = root.appendingPathComponent(directory).path
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: path,
                    isDirectory: &isDirectory
                ),
                "Capture Shell is missing its \(directory) owner"
            )
            XCTAssertTrue(isDirectory.boolValue)
        }
    }

    func testCaptureControlSurfaceIsFeatureOwned() throws {
        let repository = try repositoryRoot()
        for path in [
            "apps/ios/Merian/Core/UI/Components/CaptureControlBar.swift",
            "apps/ios/Merian/Core/UI/Components/CaptureFlashButton.swift"
        ] {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: repository.appendingPathComponent(path).path
                ),
                "Retired Core UI Capture control returned at \(path)"
            )
        }

        let controlsRoot = try shellSourceRoot().appendingPathComponent(
            "Components/CaptureControls"
        )
        for filename in [
            "CaptureControlBar.swift",
            "CaptureFlashButton.swift",
            "CapturePrimaryActionButton.swift",
            "CaptureSecondaryControlButtons.swift"
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: controlsRoot.appendingPathComponent(filename).path
                ),
                "Capture Shell is missing \(filename)"
            )
        }

        let leafControlTypes = [
            "CapturePrimaryActionButton",
            "CaptureDescribeDictationButton",
            "CaptureVideoCancelButton",
            "CapturePromptListButton",
            "CaptureAudioDeleteButton",
            "CaptureAudioDoneButton",
            "CaptureAudioReviewPlayButton",
            "CaptureFlashButton"
        ]
        let productionRoot = repository.appendingPathComponent(
            "apps/ios/Merian"
        )
        let controlsPrefix = controlsRoot.path + "/"
        for file in try swiftFiles(in: productionRoot)
            where !file.path.hasPrefix(controlsPrefix) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for leafControlType in leafControlTypes {
                XCTAssertFalse(
                    contents.contains(leafControlType),
                    "\(file.lastPathComponent) bypasses CaptureControlBar " +
                        "with \(leafControlType)"
                )
            }
        }

        let sharedModelsRoot = repository.appendingPathComponent(
            "apps/ios/Merian/Features/Capture/Shared/Models"
        )
        for filename in [
            "CaptureControlBarLayout.swift",
            "CaptureControlHapticPolicy.swift",
            "CaptureMode.swift"
        ] {
            let file = sharedModelsRoot.appendingPathComponent(filename)
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertLessThanOrEqual(
                contents.split(
                    separator: "\n",
                    omittingEmptySubsequences: false
                ).count,
                150,
                "\(filename) exceeds the focused shared-model ceiling"
            )
            for token in [
                "import SwiftUI",
                "import UIKit",
                "HapticManager",
                "UIApplication.shared",
                "AppTelemetry"
            ] {
                XCTAssertFalse(
                    contents.contains(token),
                    "\(filename) directly owns \(token)"
                )
            }
        }
    }

    func testNavigationAndModeChromeAreCaptureOwned() throws {
        let repository = try repositoryRoot()
        for path in [
            "apps/ios/Merian/Core/UI/Components/FloatingNavigationMenu.swift",
            "apps/ios/Merian/Core/UI/Components/MainTabBar.swift",
            "apps/ios/Merian/Core/UI/Components/MediaModeToggle.swift",
            "apps/ios/MerianTests/Core/UI/MediaModeToggleTests.swift"
        ] {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: repository.appendingPathComponent(path).path
                ),
                "Retired Core UI ownership returned at \(path)"
            )
        }

        let shellRoot = try shellSourceRoot()
        for path in [
            "Components/Navigation/FloatingNavigationMenu.swift",
            "Components/Navigation/MainTabBar.swift",
            "Components/ModeSelector/CaptureModeSelectorStyle.swift",
            "Components/ModeSelector/MediaModeToggle.swift",
            "Models/CaptureNavigationBadgeSnapshot.swift",
            "Services/CaptureNavigationDependencies.swift",
            "ViewModels/CaptureNavigationViewModel.swift"
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: shellRoot.appendingPathComponent(path).path
                ),
                "Capture Shell is missing \(path)"
            )
        }

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: repository.appendingPathComponent(
                    "apps/ios/MerianTests/Features/Capture/Shell/" +
                        "MediaModeToggleTests.swift"
                ).path
            )
        )
    }

    func testPrimaryControlFencesPendingPressAcrossLifecycleChanges() throws {
        let controlsRoot = try shellSourceRoot().appendingPathComponent(
            "Components/CaptureControls"
        )
        let primaryAction = try String(
            contentsOf: controlsRoot.appendingPathComponent(
                "CapturePrimaryActionButton.swift"
            ),
            encoding: .utf8
        )
        for lifecycleFence in [
            ".onChange(of: presentation.captureMode)",
            ".onChange(of: scenePhase)",
            ".onChange(of: isInteractionEnabled)",
            "invalidatePendingPress(awaitingRelease: true)",
            "guard pressState != .idle else { return }",
            "guard completedPressState != .cancelled else { return }"
        ] {
            XCTAssertTrue(
                primaryAction.contains(lifecycleFence),
                "Primary Capture action is missing \(lifecycleFence)"
            )
        }
        XCTAssertFalse(primaryAction.contains("isProVideoAvailable"))

        let controlBar = try String(
            contentsOf: controlsRoot.appendingPathComponent(
                "CaptureControlBar.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            controlBar.contains(
                "if viewModel.isCaptureControlProVideoAvailable"
            ),
            "Capture bar must read Pro eligibility when the hold matures"
        )
    }

    func testViewsComponentsAndModifiersDoNotResolveLiveServices() throws {
        let root = try shellSourceRoot()
        let presentationDirectories = ["Views", "Components", "Modifiers"]
        let forbiddenTokens = [
            "MerianNetworkClient.shared",
            "AppDIContainer.shared",
            "SupabaseManager.shared",
            "RevenueCatManager.shared",
            "HapticManager.shared",
            "NotificationCenter.default",
            "UIApplication.shared",
            "PHPhotoLibrary.shared",
            "URLSession(",
            ".client.from("
        ]

        for directory in presentationDirectories {
            let files = try swiftFiles(
                in: root.appendingPathComponent(directory)
            )
            for file in files {
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

    func testViewModelsDoNotOwnNetworkSessionsOrClients() throws {
        let root = try shellSourceRoot().appendingPathComponent("ViewModels")
        let forbiddenTokens = [
            "MerianNetworkClient.shared",
            "URLSession(",
            "URLSessionConfiguration",
            ".client.from("
        ]

        for file in try swiftFiles(in: root) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    contents.contains(token),
                    "\(file.lastPathComponent) directly owns \(token)"
                )
            }
        }
    }

    func testModelsDoNotResolveLiveStateOrPlatformActions() throws {
        let root = try shellSourceRoot().appendingPathComponent("Models")
        let forbiddenTokens = [
            "UIApplication.shared",
            "AppDIContainer.shared",
            "ExploreShareStateStore.sharedPostId",
            "UITestSeedCoordinator.",
            "HapticManager.shared",
            "MerianNetworkClient.shared",
            "UserDefaults.standard",
            "URLSession("
        ]

        for file in try swiftFiles(in: root) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    contents.contains(token),
                    "\(file.lastPathComponent) directly owns \(token)"
                )
            }
        }
    }

    func testModelsDoNotImportUIFrameworks() throws {
        let root = try shellSourceRoot().appendingPathComponent("Models")
        let forbiddenImports = ["import SwiftUI", "import UIKit"]

        for file in try swiftFiles(in: root) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for forbiddenImport in forbiddenImports {
                XCTAssertFalse(
                    contents.contains(forbiddenImport),
                    "\(file.lastPathComponent) imports \(forbiddenImport)"
                )
            }
        }
    }

    private func shellSourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/Capture/Shell"
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
        ) else { return [] }

        return try enumerator.compactMap { element in
            guard let url = element as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: keys).isRegularFile == true else {
                return nil
            }
            return url
        }
    }
}
