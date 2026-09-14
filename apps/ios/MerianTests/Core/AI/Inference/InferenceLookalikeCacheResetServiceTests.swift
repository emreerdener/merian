import SwiftData
import Testing

@testable import Merian

@MainActor
@Suite("Inference Lookalike Cache Reset Service")
struct InferenceLookalikeCacheResetServiceTests {
    @Test func resetIsScheduledOnlyWhenRequiredAndAContainerExists()
        throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        var needsReset = true
        var scheduledContainers: [ModelContainer] = []
        let service = InferenceLookalikeCacheResetService(
            dependencies: .init(
                needsReset: { needsReset },
                scheduleReset: { scheduledContainers.append($0) }
            )
        )

        #expect(service.needsReset)
        service.scheduleIfNeeded(in: nil)
        #expect(scheduledContainers.isEmpty)

        service.scheduleIfNeeded(in: container)
        #expect(scheduledContainers.count == 1)
        #expect(scheduledContainers.first === container)

        needsReset = false
        #expect(!service.needsReset)
        service.scheduleIfNeeded(in: container)
        #expect(scheduledContainers.count == 1)
    }
}
