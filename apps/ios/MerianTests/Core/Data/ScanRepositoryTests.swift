import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
@Suite(.sharedProcessState(.offlineQueueManager))
struct ScanRepositoryTests {}

enum ScanRepositoryTestSupport {
    @MainActor
    static func makeContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let storeURL = URL.cachesDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return ModelContext(container)
    }
}
