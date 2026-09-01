import Foundation
import Testing

@testable import Merian

@Suite("Inference Architecture")
struct InferenceArchitectureTests {
    @Test func extractedOwnersRemainSmallAndExplicit() throws {
        for relativePath in [
            "State/InferenceWriteCoordinator.swift",
            "Hydration/InferenceHydrationCoordinator.swift"
        ] {
            let file = try sourceRoot().appendingPathComponent(relativePath)
            #expect(
                FileManager.default.fileExists(atPath: file.path),
                "Inference is missing its \(relativePath) owner"
            )
            let lineCount = try contents(of: file)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(
                lineCount <= 600,
                "\(file.lastPathComponent) has \(lineCount) lines"
            )
        }
    }

    @Test func engineDoesNotReclaimExtractedMutableOrWireState() throws {
        let source = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/InferenceEngine.swift"
            )
        )

        #expect(source.contains("private let speciesReferenceService:"))
        #expect(source.contains("private let hydrationCoordinator:"))
        #expect(source.contains("private let writeCoordinator"))
        #expect(source.contains("resetEnrichmentRateLimit()"))
        #expect(source.contains("replaceAndAwaitTask("))
        #expect(source.contains("in: .review"))
        #expect(!source.contains("in: .gbif"))
        for retiredToken in [
            "externalAPISession",
            "WikiMobileSectionsResponse",
            "GBIFMediaResponse",
            "backgroundWriteTasks =",
            "pendingBackgroundTasks:",
            "identificationReviewWriteTail",
            "historicHydrationTask",
            "liveHydrationTask",
            "gbifHydrationTask",
            "enrichmentWriteTask",
            "wikiFetchAttemptedIds",
            "enrichmentAttemptedScanIds",
            "enrichmentRateLimitedUntil",
            "private var enrichedSpeciesTimestamps"
        ] {
            #expect(
                !source.contains(retiredToken),
                "InferenceEngine reclaimed \(retiredToken)"
            )
        }
    }

    @Test func coordinatorKeepsItsMutableTaskStatePrivate() throws {
        let writeSource = try contents(
            of: sourceRoot().appendingPathComponent(
                "State/InferenceWriteCoordinator.swift"
            )
        )

        for declaration in [
            "private var activeTasks",
            "private var pendingTasks",
            "private var reviewActionGenerations",
            "private var confirmationActionGenerations",
            "private var flagActionGenerations",
            "private var reviewWriteTail"
        ] {
            #expect(writeSource.contains(declaration))
        }

        let hydrationSource = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceHydrationCoordinator.swift"
            )
        )
        for declaration in [
            "private var activeTasks",
            "private var currentTaskIds",
            "private var wikipediaHydrationSuccesses",
            "private var historicEnrichmentAttempts",
            "private var enrichedSpeciesTimestamps",
            "private var rateLimitedUntil"
        ] {
            #expect(hydrationSource.contains(declaration))
        }
        #expect(hydrationSource.contains("case review"))
        #expect(hydrationSource.contains("func replaceAndAwaitTask("))
        #expect(!hydrationSource.contains("case gbif"))
        #expect(!writeSource.contains("@unchecked Sendable"))
        #expect(!hydrationSource.contains("@unchecked Sendable"))
    }

    @Test func hydrationOrchestrationKeepsReferenceWorkStructured() throws {
        let source = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/InferenceEngine.swift"
            )
        )
        let enrichmentStart = try #require(
            source.range(of: "func fetchAndApplyEnrichment(")
        )
        let reviewStart = try #require(
            source.range(
                of: "// MARK: - Identification Override",
                range: enrichmentStart.upperBound..<source.endIndex
            )
        )
        let enrichmentSource = source[
            enrichmentStart.lowerBound..<reviewStart.lowerBound
        ]
        let liveHydrationStart = try #require(
            source.range(of: "func schedulePostInferenceHydrationIfNeeded(")
        )
        let liveAnalysisStart = try #require(
            source.range(
                of: "func analyze(",
                range: liveHydrationStart.upperBound..<source.endIndex
            )
        )
        let liveHydrationSource = source[
            liveHydrationStart.lowerBound..<liveAnalysisStart.lowerBound
        ]

        #expect(!enrichmentSource.contains("fetchGBIFImagesAndHydrate("))
        #expect(
            !liveHydrationSource.split(separator: "\n").contains {
                $0.trimmingCharacters(in: .whitespaces)
                    .hasPrefix("Task {")
            }
        )
        #expect(!liveHydrationSource.contains("MainActor.run"))
        #expect(source.contains("let hydrationScientificName = displayScientificName"))
        #expect(source.contains("for: hydrationScientificName"))
        #expect(source.contains("enrichOnCacheMiss: false"))
        #expect(source.contains("replacingSpeciesIdentity: false"))
        #expect(source.contains("channel: .confirmation"))
        #expect(
            source.contains(
                "let imageUrl = ExternalReferenceImagePolicy.sanitizedURL("
            )
        )
        #expect(source.contains("let newUrls = fetchedURLs.compactMap"))
        #expect(
            source.contains(
                "ExternalReferenceImagePolicy.sanitizedURLList("
            )
        )
    }

    @Test func identificationReviewKeepsAdmissionAndHydrationOrdering() throws {
        let source = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/InferenceEngine.swift"
            )
        )
        let applyStart = try #require(
            source.range(of: "func applyIdentificationOverride(")
        )
        let confirmStart = try #require(
            source.range(
                of: "func confirmAIIdentification(",
                range: applyStart.upperBound..<source.endIndex
            )
        )
        let resetStart = try #require(
            source.range(
                of: "func resetIdentificationReview(",
                range: confirmStart.upperBound..<source.endIndex
            )
        )
        let applySource = source[
            applyStart.lowerBound..<confirmStart.lowerBound
        ]
        let admissionAwait = try #require(
            applySource.range(of: "await localOverrideAdmission?.value")
        )
        let hydrationStart = try #require(
            applySource.range(of: "replaceAndAwaitTask(")
        )
        #expect(applySource.contains("beginScanIdentificationOverride("))
        #expect(admissionAwait.lowerBound < hydrationStart.lowerBound)

        let confirmationSource = source[
            confirmStart.lowerBound..<resetStart.lowerBound
        ]
        #expect(confirmationSource.contains("channel: .confirmation"))
        #expect(
            confirmationSource.contains(
                "speciesData?.userIdentificationOverride == nil"
            )
        )
        #expect(
            !confirmationSource.contains("beginIdentificationReviewAction(")
        )
    }

    private func sourceRoot() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/AI/Inference"
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
