import XCTest

@testable import Merian

final class UserPersonaTests: XCTestCase {
    func testSpeciesCountBoundariesSelectExpectedPersona() {
        let cases: [(speciesCount: Int, expected: UserPersona)] = [
            (0, .observer),
            (1, .explorer),
            (9, .explorer),
            (10, .naturalist),
            (49, .naturalist),
            (50, .scholar),
            (99, .scholar),
            (100, .apexObserver),
        ]

        for testCase in cases {
            XCTAssertEqual(
                UserPersona(speciesCount: testCase.speciesCount),
                testCase.expected,
                "Unexpected persona at \(testCase.speciesCount) species"
            )
        }
    }

    func testNextLevelMetadataMatchesTierBoundaries() {
        XCTAssertEqual(UserPersona.observer.nextLevelThreshold, 1)
        XCTAssertEqual(UserPersona.observer.nextLevelTitle, "Casual Explorer")
        XCTAssertEqual(UserPersona.explorer.nextLevelThreshold, 10)
        XCTAssertEqual(UserPersona.explorer.nextLevelTitle, "Dedicated Naturalist")
        XCTAssertEqual(UserPersona.naturalist.nextLevelThreshold, 50)
        XCTAssertEqual(UserPersona.naturalist.nextLevelTitle, "Verified Scholar")
        XCTAssertEqual(UserPersona.scholar.nextLevelThreshold, 100)
        XCTAssertEqual(UserPersona.scholar.nextLevelTitle, "Apex Observer")
        XCTAssertNil(UserPersona.apexObserver.nextLevelThreshold)
        XCTAssertNil(UserPersona.apexObserver.nextLevelTitle)
    }
}
