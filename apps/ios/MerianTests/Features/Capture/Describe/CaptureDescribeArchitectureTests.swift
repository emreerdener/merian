import Foundation
import XCTest

@testable import Merian

final class CaptureDescribeArchitectureTests: XCTestCase {
    func testProductionDescribeFilesStayBelowSixHundredLines() throws {
        let files = try swiftFiles(in: describeSourceRoot())

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

    func testDescribeOwnershipDirectoriesRemainPresent() throws {
        let root = try describeSourceRoot()
        for directory in ["Models", "Services", "ViewModels", "Views", "Components"] {
            var isDirectory: ObjCBool = false
            let path = root.appendingPathComponent(directory).path
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: path,
                    isDirectory: &isDirectory
                ),
                "Capture Describe is missing its \(directory) owner"
            )
            XCTAssertTrue(isDirectory.boolValue)
        }

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Managers").path
        ))
    }

    func testViewsAndComponentsDoNotResolveLiveServices() throws {
        let root = try describeSourceRoot()
        let forbiddenTokens = [
            "AppDIContainer.shared",
            "HapticManager.shared",
            "MerianNetworkClient.shared",
            "SupabaseManager.shared",
            "RevenueCatManager.shared",
            "UIApplication.shared",
            "UserDefaults.standard",
            "URLSession(",
            ".client.from("
        ]

        for directory in ["Views", "Components"] {
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
        let root = try describeSourceRoot().appendingPathComponent("Models")
        let forbiddenTokens = [
            "import AVFoundation",
            "import Speech",
            "import SwiftUI",
            "import UIKit",
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

    func testViewModelsDoNotConstructLiveHardwareAdapters() throws {
        let root = try describeSourceRoot().appendingPathComponent("ViewModels")
        let forbiddenTokens = [
            "SpeechManager",
            "HapticManager.shared",
            "UIApplication.shared",
            "UserDefaults.standard"
        ]

        for file in try swiftFiles(in: root) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    contents.contains(token),
                    "\(file.lastPathComponent) constructs live dependency \(token)"
                )
            }
        }
    }

    func testSharedSpeechManagerLivesInCoreHardware() throws {
        let repository = try repositoryRoot()
        let coreManager = repository.appendingPathComponent(
            "apps/ios/Merian/Core/Hardware/SpeechManager.swift"
        )
        let featureManager = try describeSourceRoot().appendingPathComponent(
            "Managers/SpeechManager.swift"
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: coreManager.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: featureManager.path))
    }

    private func describeSourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/Capture/Describe"
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
