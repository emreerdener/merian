import Foundation
import Testing

@testable import Merian

@Suite("Explore Location Sharing API Models")
struct ExploreLocationSharingAPIModelsTests {
    @Test func rawValuesAndCompatibilityDecodingRemainStable() throws {
        #expect(ExplorePostLocationSharing.open.rawValue == "open")
        #expect(ExplorePostLocationSharing.obscured.rawValue == "obscured")
        #expect(ExplorePostLocationSharing.privateLocation.rawValue == "private")

        let decoder = JSONDecoder()
        #expect(try decode("open", using: decoder) == .open)
        #expect(try decode("obscured", using: decoder) == .obscured)
        #expect(try decode("private", using: decoder) == .privateLocation)
        #expect(try decode("hidden", using: decoder) == .privateLocation)
        #expect(try decode("OPEN", using: decoder) == .open)
        #expect(try decode("future-mode", using: decoder) == .obscured)
    }

    private func decode(
        _ value: String,
        using decoder: JSONDecoder
    ) throws -> ExplorePostLocationSharing {
        try decoder.decode(
            ExplorePostLocationSharing.self,
            from: Data("\"\(value)\"".utf8)
        )
    }
}
