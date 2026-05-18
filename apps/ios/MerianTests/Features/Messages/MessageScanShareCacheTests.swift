import Foundation
import XCTest
@testable import Merian

final class MessageScanShareCacheTests: XCTestCase {
    private var temporaryRootURL: URL!

    override func setUpWithError() throws {
        temporaryRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("merian-message-cache-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRootURL {
            try? FileManager.default.removeItem(at: temporaryRootURL)
        }
        temporaryRootURL = nil
    }

    func testCacheSnapshotRoundTripsThroughInjectedRootURL() throws {
        let record = makeRecord(
            id: "scan-1",
            publicExplorePostId: "post-1",
            thumbnailFilename: "thumb-scan-1.jpg",
            attachmentFilename: "attachment-scan-1.jpg"
        )
        let snapshot = MessageScanShareCacheSnapshot(
            generatedAt: Date(timeIntervalSince1970: 10),
            records: [record]
        )

        try MessageScanShareCacheStore.writeSnapshot(
            snapshot,
            rootURL: temporaryRootURL
        )

        let loaded = MessageScanShareCacheStore.loadSnapshot(rootURL: temporaryRootURL)
        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(
            MessageScanShareCacheStore.thumbnailURL(for: record, rootURL: temporaryRootURL)?.lastPathComponent,
            "thumb-scan-1.jpg"
        )
        XCTAssertEqual(
            MessageScanShareCacheStore.attachmentURL(for: record, rootURL: temporaryRootURL)?.lastPathComponent,
            "attachment-scan-1.jpg"
        )
    }

    func testDescriptionExcludesPrivateFieldNotesByDefault() {
        let record = makeRecord(fieldNotes: "Private garden note", publicExplorePostId: "post-1")

        let text = MessageScanShareTextBuilder.descriptionText(for: record)

        XCTAssertTrue(text.contains("I found Monarch Butterfly (Danaus plexippus) with Merian."))
        XCTAssertTrue(text.contains("https://merian.earth/explore/post/post-1"))
        XCTAssertFalse(text.contains("Private garden note"))
    }

    func testDescriptionIncludesFieldNotesOnlyWhenRequested() {
        let record = makeRecord(fieldNotes: "Private garden note")

        let text = MessageScanShareTextBuilder.descriptionText(
            for: record,
            includeFieldNotes: true
        )

        XCTAssertTrue(text.contains("Notes: Private garden note"))
    }

    func testMerianDeepLinkParsing() {
        XCTAssertEqual(
            MerianDeepLinkRoute(url: URL(string: "merian://scan/abc-123")!),
            .scan("abc-123")
        )
        XCTAssertEqual(
            MerianDeepLinkRoute(url: URL(string: "merian://scans")!),
            .scansLibrary
        )
        XCTAssertEqual(
            MerianDeepLinkRoute(url: URL(string: "merian://explore/post/post-123")!),
            .explorePost("post-123")
        )
        XCTAssertNil(MerianDeepLinkRoute(url: URL(string: "merian://scan")!))
        XCTAssertNil(MerianDeepLinkRoute(url: URL(string: "https://merian.earth")!))
    }

    private func makeRecord(
        id: String = "scan-1",
        fieldNotes: String? = nil,
        publicExplorePostId: String? = nil,
        thumbnailFilename: String? = nil,
        attachmentFilename: String? = nil
    ) -> MessageScanShareCacheRecord {
        MessageScanShareCacheRecord(
            id: id,
            commonName: "Monarch Butterfly",
            scientificName: "Danaus plexippus",
            timestamp: Date(timeIntervalSince1970: 1_769_436_000),
            locationName: "Austin, TX",
            confidenceScore: 0.98,
            thumbnailFilename: thumbnailFilename,
            attachmentFilename: attachmentFilename,
            publicExplorePostId: publicExplorePostId,
            fieldNotes: fieldNotes
        )
    }
}
