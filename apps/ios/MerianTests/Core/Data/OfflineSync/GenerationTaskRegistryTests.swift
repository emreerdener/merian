@testable import Merian
import XCTest

@MainActor
final class GenerationTaskRegistryTests: XCTestCase {
    func testGenerationTaskRegistryUsesCompareBeforeClear() {
        let registry = GenerationTaskRegistry<String>()
        let firstOwner = UUID()
        let secondOwner = UUID()
        let firstToken = registry.replace(
            for: "scan-a",
            ownerGeneration: firstOwner
        ) { _ in Task {} }
        let secondToken = registry.replace(
            for: "scan-a",
            ownerGeneration: secondOwner
        ) { _ in Task {} }

        XCTAssertFalse(
            registry.clearIfCurrent("scan-a", token: firstToken)
        )
        registry.cancel("scan-a", ifOwnedBy: firstOwner)
        XCTAssertFalse(registry.isOwned("scan-a", by: firstOwner))
        XCTAssertTrue(registry.isOwned("scan-a", by: secondOwner))
        XCTAssertTrue(
            registry.isCurrent(
                "scan-a",
                token: secondToken,
                ownerGeneration: secondOwner
            )
        )

        registry.cancelAll()
        XCTAssertEqual(registry.count, 0)
    }
}
