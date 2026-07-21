import Foundation
@testable import Merian
import UIKit
import XCTest

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

    func testDescriptionUsesShortShareCopy() {
        let record = makeRecord(fieldNotes: "Private garden note", publicExplorePostId: "post-1")

        let text = MessageScanShareTextBuilder.descriptionText(for: record)

        XCTAssertEqual(text, "Check out this Monarch Butterfly (Danaus plexippus) I discovered!")
        XCTAssertFalse(text.contains("Private garden note"))
        XCTAssertFalse(text.contains("Austin, TX"))
        XCTAssertFalse(text.contains("https://naturebook.earth/explore/post/post-1"))
    }

    func testDescriptionDoesNotIncludeFieldNotesWhenRequested() {
        let record = makeRecord(fieldNotes: "Private garden note")

        let text = MessageScanShareTextBuilder.descriptionText(
            for: record,
            includeFieldNotes: true
        )

        XCTAssertEqual(text, "Check out this Monarch Butterfly (Danaus plexippus) I discovered!")
        XCTAssertFalse(text.contains("Private garden note"))
    }

    func testCardCaptionUsesDiscoveredLabel() {
        let record = makeRecord()

        let caption = MessageScanShareTextBuilder.cardCaption(for: record)

        XCTAssertTrue(caption.contains("Discovered"))
        XCTAssertFalse(caption.contains("Seen"))
    }

    func testCacheWriterRendersLocalImagesIntoAppGroupCache() async throws {
        let imageURL = try makeJPEGFixture(size: CGSize(width: 96, height: 48))
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let source = MessageScanShareCacheWriter.Source(
            id: "scan-1",
            commonName: "Monarch Butterfly",
            scientificName: "Danaus plexippus",
            timestamp: Date(timeIntervalSince1970: 1_769_436_000),
            locationName: "Austin, TX",
            confidenceScore: 0.98,
            publicExplorePostId: nil,
            fieldNotes: nil,
            imageURL: imageURL
        )

        await MessageScanShareCacheRenderActor.shared.writeCache(
            sources: [source],
            rootURL: temporaryRootURL,
            fileManager: .default
        )

        let snapshot = try XCTUnwrap(MessageScanShareCacheStore.loadSnapshot(rootURL: temporaryRootURL))
        let record = try XCTUnwrap(snapshot.records.first)
        let thumbnailFilename = try XCTUnwrap(record.thumbnailFilename)
        let attachmentFilename = try XCTUnwrap(record.attachmentFilename)
        let thumbnailURL = MessageScanShareCacheStore.thumbnailDirectoryURL(rootURL: temporaryRootURL)
            .appendingPathComponent(thumbnailFilename)
        let attachmentURL = MessageScanShareCacheStore.attachmentDirectoryURL(rootURL: temporaryRootURL)
            .appendingPathComponent(attachmentFilename)

        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachmentURL.path))

        let thumbnailImage = try XCTUnwrap(UIImage(contentsOfFile: thumbnailURL.path))
        let attachmentImage = try XCTUnwrap(UIImage(contentsOfFile: attachmentURL.path))
        XCTAssertEqual(thumbnailImage.size.width, thumbnailImage.size.height)
        XCTAssertEqual(attachmentImage.size.width, attachmentImage.size.height)
    }

    func testMerianDeepLinkParsingAcceptsNaturebookAndLegacyLinks() {
        let speciesId = "1cf79982-e5ee-4e3d-8d65-274527e6ae01"

        XCTAssertEqual(
            MerianDeepLinkRoute(url: URL(string: "naturebook://scan/abc-123")!),
            .scan("abc-123")
        )
        XCTAssertEqual(
            MerianDeepLinkRoute(url: URL(string: "naturebook://scans")!),
            .scansLibrary
        )
        XCTAssertEqual(
            MerianDeepLinkRoute(url: URL(string: "naturebook://explore/post/post-123")!),
            .explorePost("post-123")
        )
        XCTAssertEqual(
            MerianDeepLinkRoute(url: URL(string: "https://naturebook.earth/explore/post/post-123")!),
            .explorePost("post-123")
        )
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
        XCTAssertEqual(
            MerianDeepLinkRoute(url: URL(string: "https://merian.earth/explore/post/post-123")!),
            .explorePost("post-123")
        )
        XCTAssertEqual(
            MerianDeepLinkRoute(url: URL(string: "https://naturebook.earth/species/\(speciesId)")!),
            .speciesDictionary(speciesId)
        )
        XCTAssertEqual(
            MerianDeepLinkRoute(
                url: URL(
                    string: "https://naturebook.earth/species/\(speciesId)/mwanza-flat-headed-rock-agama"
                )!
            ),
            .speciesDictionary(speciesId)
        )
        XCTAssertEqual(
            MerianDeepLinkRoute(
                url: URL(string: "https://merian.earth/species/\(speciesId.uppercased())/stale-name")!
            ),
            .speciesDictionary(speciesId)
        )
        XCTAssertEqual(
            MerianDeepLinkRoute(url: URL(string: "naturebook://species/\(speciesId)")!),
            .speciesDictionary(speciesId)
        )
        XCTAssertEqual(
            MerianDeepLinkRoute(url: URL(string: "merian://species/\(speciesId)")!),
            .speciesDictionary(speciesId)
        )
        XCTAssertNil(MerianDeepLinkRoute(url: URL(string: "merian://scan")!))
        XCTAssertNil(MerianDeepLinkRoute(url: URL(string: "naturebook://species/not-a-uuid")!))
        XCTAssertNil(MerianDeepLinkRoute(url: URL(string: "https://naturebook.earth/species/not-a-uuid")!))
        XCTAssertNil(
            MerianDeepLinkRoute(
                url: URL(string: "https://naturebook.earth/species/\(speciesId)/extra/path")!
            )
        )
        XCTAssertNil(MerianDeepLinkRoute(url: URL(string: "https://merian.earth")!))
        XCTAssertNil(MerianDeepLinkRoute(url: URL(string: "https://merian.earth/privacy")!))
        XCTAssertNil(MerianDeepLinkRoute(url: URL(string: "https://naturebook.app/explore/post/post-123")!))
        XCTAssertNil(MerianDeepLinkRoute(url: URL(string: "https://example.com/explore/post/post-123")!))
    }

    func testMerianDeepLinkGenerationUsesCanonicalNaturebookScheme() {
        XCTAssertEqual(
            MerianDeepLinkRoute.scan("abc-123").url?.absoluteString,
            "naturebook://scan/abc-123"
        )
        XCTAssertEqual(
            MerianDeepLinkRoute.scansLibrary.url?.absoluteString,
            "naturebook://scans"
        )
        XCTAssertEqual(
            MerianDeepLinkRoute.speciesDictionary("1cf79982-e5ee-4e3d-8d65-274527e6ae01").url?.absoluteString,
            "naturebook://species/1cf79982-e5ee-4e3d-8d65-274527e6ae01"
        )
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

    private func makeJPEGFixture(size: CGSize = CGSize(width: 24, height: 24)) throws -> URL {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        let url = temporaryRootURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        try data.write(to: url, options: [.atomic])
        return url
    }
}
