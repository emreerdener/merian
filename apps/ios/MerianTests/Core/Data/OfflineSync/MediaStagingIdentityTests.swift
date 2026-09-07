@testable import Merian
import XCTest

final class MediaStagingIdentityTests: XCTestCase {
    func test_stagingOwnerComesFromCanonicalServerIssuedKey() {
        let authenticatedOwner = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let fileName = "scan123_image.webp"
        let serverKey = "staging/\(authenticatedOwner)/\(fileName)"

        XCTAssertTrue(
            MediaStagingContract.isCanonicalObjectKey(
                serverKey,
                fileName: fileName
            )
        )
        XCTAssertEqual(
            MediaStagingContract.ownerId(fromObjectKey: serverKey),
            authenticatedOwner
        )
    }

    func test_predictedDeviceIdentityCannotOverrideServerIssuedOwner() {
        let predictedDeviceOwner = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let authenticatedOwner = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let serverKey = "staging/\(authenticatedOwner)/scan123_image.webp"

        XCTAssertNotEqual(
            MediaStagingContract.ownerId(fromObjectKey: serverKey),
            predictedDeviceOwner
        )
        XCTAssertEqual(
            MediaStagingContract.ownerId(fromObjectKey: serverKey),
            authenticatedOwner
        )
    }
}
