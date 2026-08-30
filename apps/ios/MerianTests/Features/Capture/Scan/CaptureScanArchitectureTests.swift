import Foundation
import XCTest

@testable import Merian

final class CaptureScanArchitectureTests: XCTestCase {
    func testProductionScanFilesStayBelowSixHundredLines() throws {
        let files = try swiftFiles(in: scanSourceRoot())

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

    func testScanOwnershipDirectoriesRemainPresent() throws {
        let root = try scanSourceRoot()
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
                "Capture Scan is missing its \(directory) owner"
            )
            XCTAssertTrue(isDirectory.boolValue)
        }
    }

    func testScanHasNoAggregateCaptureFileOrGlobalServiceResolution() throws {
        let root = try scanSourceRoot()
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(
                "ViewModels/Capture.swift"
            ).path
        ))

        let forbiddenTokens = [
            "AppDIContainer.shared",
            "MerianNetworkClient.shared",
            "SupabaseManager.shared",
            "RevenueCatManager.shared",
            "HapticManager.shared",
            "URLSession(",
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

    func testScanModelsRemainPlatformNeutral() throws {
        let root = try scanSourceRoot().appendingPathComponent("Models")
        let forbiddenImports = [
            "import AVFoundation",
            "import SwiftUI",
            "import UIKit"
        ]

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

    private func scanSourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/Capture/Scan"
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
