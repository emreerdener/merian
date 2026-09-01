import Foundation
import Testing

@testable import Merian

@Suite("Species Reference Hydration Architecture")
struct SpeciesHydrationArchitectureTests {
    @Test func sharedOwnerRemainsSmallAndTransportOnly() throws {
        let source = try contents(of: serviceFile())
        let lineCount = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .count

        #expect(lineCount <= 600)
        #expect(source.contains("private static let externalSession"))
        #expect(source.contains("private struct WikiMobileSectionsResponse"))
        #expect(source.contains("private struct GBIFMediaResponse"))
        for forbidden in [
            "import SwiftData",
            "import SwiftUI",
            "import UIKit",
            "MerianNetworkClient",
            "SupabaseManager",
            "ModelContext",
            "SpeciesData"
        ] {
            #expect(!source.contains(forbidden), "Service resolves \(forbidden)")
        }
    }

    @Test func inferenceAndThumbnailRecoveryReuseTheSharedOwner() throws {
        let root = try repositoryRoot()
        let inferenceFile = root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/InferenceEngine.swift"
        )
        let thumbnailFile = root.appendingPathComponent(
            "apps/ios/Merian/Core/Data/Images/ScanThumbnailBackfillActor.swift"
        )

        for consumer in [inferenceFile, thumbnailFile] {
            let source = try contents(of: consumer)
            #expect(source.contains("SpeciesReferenceHydrationService"))
            for retiredToken in [
                "api/rest_v1/page/mobile-sections",
                "occurrence/search?taxonKey=",
                "WikiMobileSectionsResponse",
                "GBIFMediaResponse",
                "externalAPISession",
                "stripHTML("
            ] {
                #expect(
                    !source.contains(retiredToken),
                    "\(consumer.lastPathComponent) reclaimed \(retiredToken)"
                )
            }
        }

        let inferenceSource = try contents(of: inferenceFile)
        #expect(
            inferenceSource.contains(
                "let descriptionText = reference.overview"
            )
        )
        let thumbnailSource = try contents(of: thumbnailFile)
        #expect(
            thumbnailSource.contains(
                "primary: wikipediaReference?.imageURL"
            )
        )
    }

    private func serviceFile() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/SpeciesReference/Services/SpeciesReferenceHydrationService.swift"
        )
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

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }
}
