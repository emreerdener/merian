import Foundation
@testable import Merian
import XCTest

final class OAuthSignInModelsTests: XCTestCase {
    func testProfileMetadataTrimsValuesAndDropsEmptyFields() {
        let metadata = OAuthProfileMetadata(
            displayName: "  Ada Lovelace  ",
            givenName: " Ada ",
            familyName: "   ",
            avatarURL: " https://example.test/avatar.jpg "
        )

        XCTAssertEqual(metadata.displayName, "Ada Lovelace")
        XCTAssertEqual(metadata.givenName, "Ada")
        XCTAssertNil(metadata.familyName)
        XCTAssertEqual(
            metadata.avatarURL,
            "https://example.test/avatar.jpg"
        )
        XCTAssertFalse(metadata.isEmpty)
    }

    func testMissingAppleNameProducesEmptyMetadata() {
        let metadata = OAuthProfileMetadata(
            appleNameComponents: nil
        )

        XCTAssertTrue(metadata.isEmpty)
    }
}
