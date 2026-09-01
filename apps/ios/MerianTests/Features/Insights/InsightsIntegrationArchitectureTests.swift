import Foundation
import Testing

@testable import Merian

@Suite("Insights integration architecture")
struct InsightsIntegrationArchitectureTests {
    @Test("Every Insights source remains within the feature line ceiling")
    func sourceLineCeiling() throws {
        let files = try swiftFiles(in: insightsSourceRoot())
        #expect(!files.isEmpty)

        for file in files {
            let source = try contents(of: file)
            let lineCount = source.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count
            #expect(
                lineCount <= 600,
                "\(file.lastPathComponent) has \(lineCount) lines"
            )
        }
    }

    @Test("Top-level ownership areas remain explicit")
    func topLevelOwnershipAreasRemainExplicit() throws {
        let root = try insightsSourceRoot()
        for directory in [
            "Content",
            "FieldNotes",
            "IdentificationReview",
            "Media",
            "Shared",
            "Sharing",
            "Shell",
            "Toolbars"
        ] {
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(
                atPath: root.appendingPathComponent(directory).path,
                isDirectory: &isDirectory
            ))
            #expect(isDirectory.boolValue)
        }
    }

    @Test("Cross-feature primitives have domain-neutral owners")
    func crossFeaturePrimitivesHaveDomainNeutralOwners() throws {
        let repositoryRoot = try repositoryRoot()
        let expectedOwners = [
            "apps/ios/Merian/Core/Media/MediaExportService.swift",
            "apps/ios/Merian/Core/UI/Components/Cards/MerianCardHeader.swift",
            "apps/ios/Merian/Core/UI/Components/Cards/ScientificNameStyler.swift",
            "apps/ios/Merian/Core/UI/Components/ModelTierBadge.swift",
            "apps/ios/Merian/Core/UI/Components/Toolbars/ScrollAwareToolbarTitleBadge.swift",
            "apps/ios/Merian/Core/UI/Feedback/ToastBanner.swift",
            "apps/ios/Merian/Core/UI/Feedback/ToxicityBanner.swift",
            "apps/ios/Merian/Features/FieldChat/Components/Toolbar/FieldChatToolbarButton.swift",
            "apps/ios/Merian/Features/SpeciesReference/README.md"
        ]
        for relativePath in expectedOwners {
            #expect(
                FileManager.default.fileExists(
                    atPath: repositoryRoot.appendingPathComponent(relativePath)
                        .path
                ),
                "Missing owner at \(relativePath)"
            )
        }

        let removedOwners = [
            "apps/ios/Merian/Features/Insights/Media/Utilities/InsightMediaExportManager.swift",
            "apps/ios/Merian/Features/Insights/Shared/Badges/ModelTierBadge.swift",
            "apps/ios/Merian/Features/Insights/Shared/Banners/ToastBanner.swift",
            "apps/ios/Merian/Features/Insights/Shared/Banners/ToxicityBanner.swift",
            "apps/ios/Merian/Features/Insights/SpeciesReference"
        ]
        for relativePath in removedOwners {
            #expect(
                !FileManager.default.fileExists(
                    atPath: repositoryRoot.appendingPathComponent(relativePath)
                        .path
                ),
                "Legacy owner remains at \(relativePath)"
            )
        }
    }

    @Test("Shared and toolbar support do not resolve live services")
    func supportViewsDoNotResolveLiveServices() throws {
        let root = try insightsSourceRoot()
        let directories = [
            root.appendingPathComponent("Shared"),
            root.appendingPathComponent("Toolbars"),
            root.appendingPathComponent("Media/Utilities")
        ]
        let forbiddenTokens = [
            "AppDIContainer.shared",
            "EntitlementManager.shared",
            "HapticManager.shared",
            "InsightMediaExportManager",
            "MerianNetworkClient.shared",
            "RevenueCatManager.shared",
            "ShareSheetUtility.present",
            "SupabaseManager.shared"
        ]

        for directory in directories {
            for file in try swiftFiles(in: directory) {
                let source = try contents(of: file)
                for token in forbiddenTokens {
                    #expect(
                        !source.contains(token),
                        "\(file.lastPathComponent) resolves \(token)"
                    )
                }
            }
        }
    }

    @Test("Media export effects stay behind session-fenced dependencies")
    func mediaExportEffectsStaySessionFenced() throws {
        let root = try insightsSourceRoot()
        let viewModel = try contents(
            of: root.appendingPathComponent(
                "Media/Utilities/InsightSheetViewModel+MediaExport.swift"
            )
        )
        let dependencies = try contents(
            of: root.appendingPathComponent(
                "Shell/Services/InsightShellDependencies.swift"
            )
        )

        #expect(viewModel.contains("mediaSaveTaskID == taskID"))
        #expect(viewModel.contains("mediaShareTaskID == taskID"))
        #expect(viewModel.contains("isPresentingLocalRecord"))
        #expect(!viewModel.contains("ShareSheetUtility.present"))
        #expect(!viewModel.contains("PhotoLibraryManager.shared"))
        #expect(dependencies.contains("let saveMedia:"))
        #expect(dependencies.contains("let prepareMediaShare:"))
        #expect(dependencies.contains("let presentMediaShare:"))
    }

    private func insightsSourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/Insights"
        )
        #expect(FileManager.default.fileExists(atPath: root.path))
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

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
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
