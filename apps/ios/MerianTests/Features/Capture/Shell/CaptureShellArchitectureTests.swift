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
