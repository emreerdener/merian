import XCTest

@testable import Merian

final class CaptureScanTemporaryFileLeaseTests: XCTestCase {
    func testUnclaimedLeaseDeletesTemporaryFileOnRelease() throws {
        let fileURL = makeTemporaryFileURL()
        try Data("temporary".utf8).write(to: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        var lease: CaptureScanTemporaryFileLease? =
            CaptureScanTemporaryFileLease(fileURL: fileURL)
        XCTAssertNotNil(lease)

        lease = nil

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testRelinquishedLeasePreservesAcceptedFile() async throws {
        let fileURL = makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("accepted".utf8).write(to: fileURL)

        var lease: CaptureScanTemporaryFileLease? =
            CaptureScanTemporaryFileLease(fileURL: fileURL)
        let acceptedURL = try await lease?.relinquishOwnership()
        lease = nil

        XCTAssertEqual(acceptedURL, fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private func makeTemporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "capture-scan-lease-\(UUID().uuidString.lowercased()).tmp"
        )
    }
}
