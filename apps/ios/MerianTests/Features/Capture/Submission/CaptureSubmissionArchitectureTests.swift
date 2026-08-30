import Foundation
import XCTest

@testable import Merian

final class CaptureSubmissionArchitectureTests: XCTestCase {
    func testProductionSubmissionFilesStayBelowSixHundredLines() throws {
        let files = try swiftFiles(in: submissionSourceRoot())

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

    func testSubmissionOwnershipDirectoriesRemainPresent() throws {
        let root = try submissionSourceRoot()
        for directory in ["Models", "Services", "ViewModels"] {
            var isDirectory: ObjCBool = false
            let path = root.appendingPathComponent(directory).path
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: path,
                    isDirectory: &isDirectory
                ),
                "Capture Submission is missing its \(directory) owner"
            )
            XCTAssertTrue(isDirectory.boolValue)
        }
    }

    func testAggregateFilesStayRemoved() throws {
        let viewModels = try submissionSourceRoot()
            .appendingPathComponent("ViewModels")
        for filename in ["Analysis.swift", "AudioAnalysis.swift", "DescribeAnalysis.swift"] {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: viewModels.appendingPathComponent(filename).path
            ))
        }
    }

    func testRequestAndReplayModelsRemainSubmissionOwned() throws {
        let models = try submissionSourceRoot().appendingPathComponent("Models")
        for filename in [
            "CaptureSubmissionMediaProjection.swift",
            "CaptureSubmissionMediaTimeline.swift",
            "IdentifyMediaDescriptors.swift"
        ] {
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: models.appendingPathComponent(filename).path
            ))
        }

        let stagingModels = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/Capture/Staging/Models"
        )
        let stagingContents = try swiftFiles(in: stagingModels)
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        for declaration in [
            "enum CaptureSubmissionMediaItem",
            "struct CaptureSubmissionMediaProjection",
            "struct IdentifyVisualMediaItem",
            "struct IdentifyAudioMediaItem",
            "struct IdentifyOwnerMediaTimelineItem"
        ] {
            XCTAssertFalse(
                stagingContents.contains(declaration),
                "Staging reintroduced Submission declaration \(declaration)"
            )
        }
    }

    func testViewModelsDoNotResolveNetworkClients() throws {
        let root = try submissionSourceRoot()
            .appendingPathComponent("ViewModels")
        let forbiddenTokens = [
            "MerianNetworkClient.shared",
            "SupabaseManager.shared",
            "ScanAdmissionManager.shared",
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

    func testModelsRemainFreeOfUIAndLiveServiceResolution() throws {
        let root = try submissionSourceRoot().appendingPathComponent("Models")
        let forbiddenTokens = [
            "import SwiftUI",
            "import UIKit",
            "AppDIContainer.shared",
            "MerianNetworkClient.shared",
            "SupabaseManager.shared",
            "RevenueCatManager.shared",
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

    func testUncheckedSendableIsAbsentFromSubmission() throws {
        for file in try swiftFiles(in: submissionSourceRoot()) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                contents.contains("@unchecked Sendable"),
                "\(file.lastPathComponent) reintroduced unchecked isolation"
            )
        }
    }

    private func submissionSourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/Capture/Submission"
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
