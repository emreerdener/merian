import Foundation
@testable import Merian
import SwiftData

enum OfflineSyncTestSupport {
    @MainActor
    static func makeIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let storeURL = URL.cachesDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return ModelContext(container)
    }

    static func loadRepositorySource(
        at relativePath: String
    ) throws -> String {
        var searchURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        for _ in 0..<8 {
            let sourceURL = searchURL.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                return try String(
                    contentsOf: sourceURL,
                    encoding: .utf8
                )
            }
            searchURL.deleteLastPathComponent()
        }

        throw CocoaError(.fileNoSuchFile)
    }

    static func normalizedSource(_ source: String) -> String {
        source
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
