import Foundation
import Testing

@testable import Merian

struct IdentificationReviewArchitectureTests {
    @Test func ownershipDirectoriesAndLineCeilingRemainPresent() throws {
        let root = try sourceRoot()
        for directory in [
            "Candidates/Models",
            "Candidates/Services",
            "Candidates/ViewModels",
            "Candidates/Views",
            "Candidates/Components/Card",
            "Candidates/Components/Review",
            "Candidates/Components/Swipe",
            "Confidence/Models",
            "Confidence/Services",
            "Confidence/ViewModels",
            "Confidence/Views",
            "Confidence/Components/Guidance",
            "Confidence/Components/ReviewState",
            "Confidence/Components/Scale",
            "Shared/Models",
            "Shared/Services"
        ] {
            var isDirectory: ObjCBool = false
            let path = root.appendingPathComponent(directory).path
            #expect(
                FileManager.default.fileExists(
                    atPath: path,
                    isDirectory: &isDirectory
                ),
                "Identification Review is missing its \(directory) owner"
            )
            #expect(isDirectory.boolValue)
        }

        for file in try swiftFiles(in: root) {
            let lineCount = try contents(of: file)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(
                lineCount <= 600,
                "\(file.lastPathComponent) has \(lineCount) lines"
            )
        }
    }

    @Test func liveEffectsRemainServicesOnly() throws {
        let forbidden = [
            "AppDIContainer.shared",
            "HapticManager.shared",
            "RevenueCatManager.shared",
            "UIApplication.shared",
            "MerianNetworkClient.shared",
            "FetchDescriptor<LocalScanRecord>",
            "inferenceEngine.confirmAIIdentification(",
            "inferenceEngine.applyIdentificationOverride(",
            "inferenceEngine.resetIdentificationReview(",
            "inferenceEngine.markAlternativesExhausted("
        ]

        for file in try swiftFiles(in: sourceRoot()) {
            guard !file.pathComponents.contains("Services") else { continue }
            let source = try contents(of: file)
            for token in forbidden {
                #expect(
                    !source.contains(token),
                    "\(file.lastPathComponent) resolves \(token)"
                )
            }
        }
    }

    @Test func presentationModelsRemainPlatformNeutral() throws {
        for modelRoot in [
            "Candidates/Models",
            "Confidence/Models",
            "Shared/Models"
        ] {
            for file in try swiftFiles(
                in: sourceRoot().appendingPathComponent(modelRoot)
            ) {
                let source = try contents(of: file)
                for forbiddenImport in [
                    "import SwiftData",
                    "import SwiftUI",
                    "import UIKit"
                ] {
                    #expect(
                        !source.contains(forbiddenImport),
                        "\(file.lastPathComponent) imports \(forbiddenImport)"
                    )
                }
            }
        }
    }

    @Test func legacyComponentLocationsAreRemoved() throws {
        let root = try sourceRoot()
        for legacyPath in [
            "Candidates/Components/CandidateAlternativesView.swift",
            "Candidates/Components/CandidateVerificationView.swift",
            "Candidates/Components/CandidatesCard.swift",
            "Candidates/Components/FlayedCandidateThumbnail.swift",
            "Candidates/Views/CandidateActionBar.swift",
            "Candidates/Views/CandidateSwipeIndicator.swift",
            "Candidates/Views/GridSwipeableCell.swift",
            "Candidates/Views/OriginalCapturePiPView.swift",
            "Candidates/Views/SwipeableCandidateCard.swift",
            "Confidence/Views/AllCandidatesReviewedView.swift",
            "Confidence/Views/ConfidenceHeader.swift",
            "Confidence/Views/ConfidenceSpectrum.swift",
            "Confidence/Views/ConfirmedView.swift",
            "Confidence/Views/ModelInfoSection.swift",
            "Confidence/Views/OverriddenView.swift",
            "Confidence/Views/ProTips.swift",
            "Confidence/Views/SpectrumNode.swift",
            "Confidence/Views/TipRow.swift"
        ] {
            #expect(
                !FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(legacyPath).path
                ),
                "Legacy Identification Review owner remains at \(legacyPath)"
            )
        }
    }

    @Test func featureDeclaresNoUncheckedSendableConformance() throws {
        for file in try swiftFiles(in: sourceRoot()) {
            let source = try contents(of: file)
            #expect(
                !source.contains("@unchecked Sendable"),
                "\(file.lastPathComponent) bypasses sendability checking"
            )
        }
    }

    private func sourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/Insights/IdentificationReview"
        )
        #expect(FileManager.default.fileExists(atPath: root.path))
        return root
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
            else { return nil }
            return url
        }
    }

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }
}
