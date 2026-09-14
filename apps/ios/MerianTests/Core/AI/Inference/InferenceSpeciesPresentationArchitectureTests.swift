import Foundation
import Testing

@testable import Merian

@Suite("Inference Species Presentation Architecture")
struct SpeciesPresentationArchitectureTests {
    @Test func bridgeIsTheOnlyProductionHydrationCallbackFactory() throws {
        let root = try inferenceRoot()
        let bridgeURL = root.appendingPathComponent(
            "Hydration/InferenceSpeciesPresentationCoordinator.swift"
        )
        let bridge = try contents(of: bridgeURL)
        let callbackOwners = try swiftFiles(in: root).filter { file in
            try contents(of: file).contains(
                "InferenceSpeciesHydrationCoordinator.Callbacks("
            )
        }

        #expect(callbackOwners == [bridgeURL])
        #expect(
            bridge.contains(
                "final class InferenceSpeciesPresentationCoordinator"
            )
        )
        #expect(bridge.contains("func makeHydrationCallbacks()"))
        #expect(bridge.contains("func makeReviewWorkflowCallbacks()"))
    }

    @Test func engineRetainsOnlyStableFacadesAndBridgeComposition() throws {
        let engine = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/InferenceEngine.swift"
            )
        )

        #expect(
            engine.contains(
                "private let speciesPresentationCoordinator:\n        InferenceSpeciesPresentationCoordinator"
            )
        )
        for requiredCall in [
            ".scheduleLiveHydrationIfNeeded(",
            "speciesPresentationCoordinator.fetchAndApplyEnrichment(",
            ".makeReviewWorkflowCallbacks()",
            "speciesPresentationCoordinator.markAlternativesExhausted("
        ] {
            #expect(engine.contains(requiredCall))
        }
        for retiredEngineOwnership in [
            "func speciesHydrationCallbacks()",
            "func identificationReviewWorkflowCallbacks()",
            "func isLiveSpeciesPresentation(",
            "func executeSpeciesMetadataWrite(",
            "func schedulePostInferenceHydrationIfNeeded(",
            "private let speciesHydrationCoordinator:",
            "private let identificationReviewCoordinator:"
        ] {
            #expect(!engine.contains(retiredEngineOwnership))
        }
    }

    @Test func bridgePreservesExactIdentityAndWriteAdmissionFences() throws {
        let source = try contents(
            of: try inferenceRoot().appendingPathComponent(
                "Hydration/InferenceSpeciesPresentationCoordinator.swift"
            )
        )

        for requiredFence in [
            "caseInsensitiveCompare(identity.scanId)",
            "caseInsensitiveCompare(\n                  identity.scientificName",
            "writeCoordinator.generation\n                == identity.presentationGeneration",
            "reviewCoordinator.isReviewActionCurrent(",
            "_ = beginReviewAction(scanId: scanId)",
            "presentationState.markAlternativesExhausted()",
            "guard !writeCoordinator.isAuthTransitionFenceActive",
            "guard !Task.isCancelled,",
            "await self.isPresentationCurrent(work.identity)",
            "reviewCoordinator.enqueueWrite(",
            "writeCoordinator.enqueueBackgroundWrite(guardedOperation)"
        ] {
            #expect(source.contains(requiredFence))
        }
    }

    @Test func bridgeOwnsNoIndependentStateOrExternalEffects() throws {
        let sourceURL = try inferenceRoot().appendingPathComponent(
            "Hydration/InferenceSpeciesPresentationCoordinator.swift"
        )
        let source = try contents(of: sourceURL)
        let lineCount = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .count

        #expect(lineCount <= 600)
        for dependency in [
            "private let presentationState:",
            "private let writeCoordinator:",
            "private let reviewCoordinator:",
            "private let speciesHydrationCoordinator:"
        ] {
            #expect(source.contains(dependency))
        }
        #expect(source.contains("private func isPresentationCurrent("))
        for forbiddenEffect in [
            "@Observable",
            "private var ",
            "Task {",
            "Task.detached",
            "URLSession",
            "SupabaseManager",
            "BackgroundDatabaseActor",
            "UserDefaults",
            "FileManager",
            "NotificationCenter",
            "MerianLog",
            ".shared",
            "static let live"
        ] {
            #expect(!source.contains(forbiddenEffect))
        }
    }

    private func swiftFiles(in root: URL) throws -> [URL] {
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        )
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }

    private func inferenceRoot() throws -> URL {
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

    private func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
