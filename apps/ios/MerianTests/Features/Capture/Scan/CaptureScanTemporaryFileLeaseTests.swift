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

    func testExplicitDiscardIsImmediateIdempotentAndCannotBeAccepted() async throws {
        let url = makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url)
        let lease = CaptureScanTemporaryFileLease(fileURL: url)
        try await lease.discard()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try await lease.discard()
        do { _ = try await lease.relinquishOwnership(); XCTFail("Discarded lease was accepted") }
        catch { XCTAssertEqual((error as? CocoaError)?.code, .fileNoSuchFile) }
    }

    func testDiscardAfterAcceptancePreservesTransferredFile() async throws {
        let url = makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url)
        let lease = CaptureScanTemporaryFileLease(fileURL: url)
        _ = try await lease.relinquishOwnership()
        try await lease.discard()
        XCTAssertEqual(try Data(contentsOf: url), Data([1]))
    }

    func testDiscardOfMissingFileIsClosed() async throws {
        let lease = CaptureScanTemporaryFileLease(fileURL: makeTemporaryFileURL())
        try await lease.discard()
        do { _ = try await lease.relinquishOwnership(); XCTFail("Absent file was accepted") }
        catch { XCTAssertEqual((error as? CocoaError)?.code, .fileNoSuchFile) }
    }

    private func makeTemporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "capture-scan-lease-\(UUID().uuidString.lowercased()).tmp"
        )
    }
}
