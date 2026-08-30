import Foundation
import XCTest

@testable import Merian

final class InsightShellArchitectureTests: XCTestCase {
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
                "Insight Shell is missing its \(directory) owner"
            )
            XCTAssertTrue(isDirectory.boolValue)
        }
    }

    func testLiveResolutionStaysInServices() throws {
        let root = try shellSourceRoot()
        let forbiddenTokens = [
            "AppDIContainer.shared",
            "MerianNetworkClient.shared",
            "SupabaseManager.shared",
            "RevenueCatManager.shared",
            "HapticManager.shared",
            "ScanRepository.shared",
            "OfflineQueueManager.shared",
            "AppSettings.shared",
            "AppIconBadgeCoordinator.updateAppIconBadge"
        ]

        for file in try swiftFiles(in: root) {
            guard !file.pathComponents.contains("Services") else { continue }
            let contents = try String(contentsOf: file, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    contents.contains(token),
                    "\(file.lastPathComponent) directly resolves \(token)"
                )
            }
        }
    }

    func testViewsAndViewModelsDoNotOwnNetworkClients() throws {
        let root = try shellSourceRoot()
        let forbiddenTokens = [
            "MerianNetworkClient",
            "URLSession(",
            "URLSessionConfiguration",
            ".client.from("
        ]
        let ownedDirectories = ["Views", "Components", "Modifiers", "ViewModels"]

        for directory in ownedDirectories {
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

    func testModelsRemainPlatformNeutral() throws {
        let root = try shellSourceRoot().appendingPathComponent("Models")
        for file in try swiftFiles(in: root) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for forbiddenImport in ["import SwiftUI", "import UIKit"] {
                XCTAssertFalse(
                    contents.contains(forbiddenImport),
                    "\(file.lastPathComponent) imports \(forbiddenImport)"
                )
            }
        }
    }

    func testFormerSourceAndTestAggregatesAreRemoved() throws {
        let root = try repositoryRoot()
        let removedAggregates = [
            "apps/ios/Merian/Features/Insights/Shell/ViewModels/InsightSheetViewModel+Display.swift",
            "apps/ios/MerianTests/Features/Insights/InsightSheetViewModelTests.swift"
        ]

        for relativePath in removedAggregates {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(relativePath).path
                ),
                "Former aggregate still exists at \(relativePath)"
            )
        }
    }

    private func shellSourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/Insights/Shell"
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
                  try url.resourceValues(forKeys: keys).isRegularFile == true
            else {
                return nil
            }
            return url
        }
    }
}
