import Foundation
@testable import Merian
import SwiftData

enum DatabaseActorTestSupport {
    struct RepositorySourceFile {
        let relativePath: String
        let contents: String
    }

    @MainActor
    static func makeIsolatedContainer() throws -> ModelContainer {
        let schema = Schema(CurrentSchema.models)
        let storeURL = URL.cachesDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    static func loadRepositorySource(
        at relativePath: String
    ) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    static func repositoryRoot() throws -> URL {
        var searchURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: searchURL.appendingPathComponent("project.yml").path
            ) {
                return searchURL
            }
            searchURL.deleteLastPathComponent()
        }

        throw CocoaError(.fileNoSuchFile)
    }

    static func lineCount(of source: String) -> Int {
        source.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    static func swiftSources(
        below relativeDirectory: String
    ) throws -> [RepositorySourceFile] {
        let root = try repositoryRoot()
            .appendingPathComponent(relativeDirectory)

        return try FileManager.default
            .subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
            .map { relativePath in
                RepositorySourceFile(
                    relativePath: relativePath,
                    contents: try String(
                        contentsOf: root.appendingPathComponent(relativePath),
                        encoding: .utf8
                    )
                )
            }
    }
}
