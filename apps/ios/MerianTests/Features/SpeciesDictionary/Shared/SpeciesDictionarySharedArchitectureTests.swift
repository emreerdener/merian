import Foundation
import Testing

@Suite("Species Dictionary Shared Architecture")
struct SpeciesDictionarySharedArchitectureTests {
    @Test func sharedModelsOwnCrossSurfacePresentationAdapters() throws {
        let root = try sharedSourceRoot()
        let models = root.appendingPathComponent("Models")
        try #require(isDirectory(models))

        let navigation = models.appendingPathComponent(
            "SpeciesDictionaryNavigation.swift"
        )
        let taxonomy = models.appendingPathComponent(
            "SpeciesDictionaryTaxonomyPresentation.swift"
        )
        let referenceImages = models.appendingPathComponent(
            "SpeciesDictionaryReferenceImagePresentation.swift"
        )
        #expect(FileManager.default.fileExists(atPath: navigation.path))
        #expect(FileManager.default.fileExists(atPath: taxonomy.path))
        #expect(FileManager.default.fileExists(atPath: referenceImages.path))

        let navigationSource = try String(
            contentsOf: navigation,
            encoding: .utf8
        )
        #expect(navigationSource.contains("struct SpeciesDictionaryRoute"))
        #expect(navigationSource.contains("enum SpeciesDictionaryEntryPoint"))

        let referenceImageSource = try String(
            contentsOf: referenceImages,
            encoding: .utf8
        )
        #expect(referenceImageSource.contains("naturebookAuthorUsername"))
        #expect(referenceImageSource.contains("fullscreenAttributionLabel"))

        for file in try swiftFiles(in: root) {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("MerianNetworkClient"))
            #expect(!source.contains("import SwiftUI"))
            let lineCount = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 600)
        }
    }

    private func sharedSourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/SpeciesDictionary/Shared"
        )
        try #require(isDirectory(root))
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

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
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
                  try url.resourceValues(
                      forKeys: keys
                  ).isRegularFile == true else {
                return nil
            }
            return url
        }
    }
}
