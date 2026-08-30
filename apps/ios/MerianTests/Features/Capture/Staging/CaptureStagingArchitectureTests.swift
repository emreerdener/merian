import Foundation
import XCTest

@testable import Merian

final class CaptureStagingArchitectureTests: XCTestCase {
    func testProductionStagingFilesStayBelowSixHundredLines() throws {
        let files = try swiftFiles(in: stagingSourceRoot())

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

    func testStagingOwnershipDirectoriesRemainPresent() throws {
        let root = try stagingSourceRoot()
        for directory in ["Models", "Views"] {
            var isDirectory: ObjCBool = false
            let path = root.appendingPathComponent(directory).path
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: path,
                    isDirectory: &isDirectory
                ),
                "Capture Staging is missing its \(directory) owner"
            )
            XCTAssertTrue(isDirectory.boolValue)
        }
    }

    func testStagingDoesNotOwnNetworkOrPersistenceResolution() throws {
        let forbiddenTokens = [
            "AppDIContainer.shared",
            "FileIOActor.shared",
            "MerianNetworkClient.shared",
            "OfflineQueueManager.shared",
            "SupabaseManager.shared",
            "RevenueCatManager.shared",
            "URLSession(",
            ".client.from("
        ]

        for file in try swiftFiles(in: stagingSourceRoot()) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    contents.contains(token),
                    "\(file.lastPathComponent) directly owns \(token)"
                )
            }
        }
    }

    func testOnlyTheStagedImageValueImportsUIKit() throws {
        let models = try stagingSourceRoot().appendingPathComponent("Models")

        for file in try swiftFiles(in: models) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let importsUIKit = contents.contains("import UIKit")
            XCTAssertEqual(
                importsUIKit,
                file.lastPathComponent == "StagedImage.swift",
                "\(file.lastPathComponent) has unexpected UIKit ownership"
            )
        }
    }

    func testRequestAndReplayDeclarationsRemainSubmissionOwned() throws {
        let stagingContents = try swiftFiles(in: stagingSourceRoot())
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let forbiddenDeclarations = [
            "enum CaptureSubmissionMediaItem",
            "struct CaptureSubmissionMediaProjection",
            "enum CaptureSubmissionProjectionItem",
            "enum IdentifyVisualMediaKind",
            "struct IdentifyVisualMediaItem",
            "enum IdentifyAudioMediaKind",
            "struct IdentifyAudioMediaItem",
            "enum IdentifyOwnerMediaKind",
            "struct IdentifyOwnerMediaTimelineItem"
        ]

        for declaration in forbiddenDeclarations {
            XCTAssertFalse(
                stagingContents.contains(declaration),
                "Staging reintroduced Submission declaration \(declaration)"
            )
        }

        let submissionModels = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/Capture/Submission/Models"
        )
        for filename in [
            "CaptureSubmissionMediaProjection.swift",
            "CaptureSubmissionMediaTimeline.swift",
            "IdentifyMediaDescriptors.swift"
        ] {
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: submissionModels.appendingPathComponent(filename).path
            ))
        }
    }

    func testToolbarConsumesCanonicalStagingOrderWithoutResorting() throws {
        let toolbar = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/UI/Components/ActiveScanToolbar.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(toolbar.contains("stagedCapture.orderedNodes.filter"))
        XCTAssertFalse(toolbar.contains("nodes.sorted"))
    }

    private func stagingSourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/Capture/Staging"
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
