import Foundation
import XCTest

@testable import Merian

final class SettingsArchitectureTests: XCTestCase {
    func testProductionSettingsFilesStayBelowSixHundredLines() throws {
        let sourceRoot = try settingsSourceRoot()
        let files = try swiftFiles(in: sourceRoot)

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

    func testSettingsViewsAndComponentsDoNotResolveLiveServices() throws {
        let sourceRoot = try settingsSourceRoot()
        let forbiddenTokens = [
            "MerianNetworkClient.shared",
            "UNUserNotificationCenter.current()",
            "AppDIContainer.shared",
            "RevenueCatManager.shared",
            "CameraManager.shared",
            "UsageManager.shared",
            "UIApplication.shared",
            "ScanRepository.shared",
            "GeoprivacySettingsDependencies.live(",
            "@Environment(HardwareOrchestrator.self)",
            "hardwareOrchestrator.evaluateConstraints(",
            ".client.from("
        ]

        let presentationFiles = try swiftFiles(in: sourceRoot).filter {
            $0.pathComponents.contains("Views") ||
                $0.pathComponents.contains("Components")
        }

        for file in presentationFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    contents.contains(token),
                    "\(file.lastPathComponent) directly owns \(token)"
                )
            }
        }
    }

    private func settingsSourceRoot() throws -> URL {
        let repositoryRoot = try repositoryRoot()
        let sourceRoot = repositoryRoot.appendingPathComponent(
            "apps/ios/Merian/Features/Profile/Settings"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceRoot.path))
        return sourceRoot
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()

        for _ in 0..<10 {
            let projectManifest = candidate.appendingPathComponent(
                "project.yml"
            )
            if FileManager.default.fileExists(
                atPath: projectManifest.path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        throw CocoaError(.fileNoSuchFile)
    }

    private func swiftFiles(in root: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys
        ) else { return [] }

        return try enumerator.compactMap { element in
            guard let url = element as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: Set(keys)).isRegularFile ==
                    true else { return nil }
            return url
        }
    }
}
