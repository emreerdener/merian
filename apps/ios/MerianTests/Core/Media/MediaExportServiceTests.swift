import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Merian

@Suite("Media export service")
struct MediaExportServiceTests {
    @Test("Resolver preserves every supported persisted media location")
    func resolverPreservesSupportedLocations() throws {
        let absoluteURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("absolute-image.webp")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("file-url-image.webp")
        let approvedURL = try #require(URL(
            string: "https://media.merian.app/cdn/image.webp"
        ))
        let suffixLookalikeURL = try #require(URL(
            string: "https://media.merian.app.example.com/image.webp"
        ))
        let externalURL = try #require(URL(
            string: "https://example.com/image.webp"
        ))

        #expect(
            MediaExportSourceResolver.localURL(from: absoluteURL.path)
                == absoluteURL
        )
        #expect(
            MediaExportSourceResolver.localURL(
                from: fileURL.absoluteString
            ) == fileURL
        )
        #expect(
            MediaExportSourceResolver.localURL(from: "relative/image.webp")?
                .path.hasSuffix("/Documents/relative/image.webp") == true
        )
        #expect(
            MediaExportSourceResolver.sources(
                from: "https://media.merian.app/cdn/image.webp"
            ) == [.approvedRemote(approvedURL)]
        )
        #expect(
            MediaExportSourceResolver.sources(
                from: "https://example.com/unapproved.webp"
            ).isEmpty
        )
        #expect(MediaExportSourceResolver.isApprovedRemoteURL(approvedURL))
        #expect(!MediaExportSourceResolver.isApprovedRemoteURL(
            suffixLookalikeURL
        ))
        #expect(!MediaExportSourceResolver.isApprovedRemoteURL(externalURL))

        let approvedRedirect = URLRequest(url: approvedURL)
        let lookalikeRedirect = URLRequest(url: suffixLookalikeURL)
        let externalRedirect = URLRequest(url: externalURL)
        #expect(
            MediaExportSourceResolver.approvedRedirectRequest(
                approvedRedirect
            )?.url == approvedURL
        )
        #expect(
            MediaExportSourceResolver.approvedRedirectRequest(
                lookalikeRedirect
            ) == nil
        )
        #expect(
            MediaExportSourceResolver.approvedRedirectRequest(
                externalRedirect
            ) == nil
        )
        #expect(MediaExportSizingPolicy.singleShareMaxPixelSize == 2_048)
        #expect(MediaExportSizingPolicy.batchShareMaxPixelSize == 1_024)
    }

    @Test("Save request normalizes local and approved remote sources")
    func saveRequestNormalizesSources() throws {
        let localVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-video.mp4")
        let remoteVideoURL = try #require(URL(
            string: "https://media.merian.app/cdn/test.mp4"
        ))
        let request = MediaSaveRequest.make(
            liveImageData: nil,
            imagePaths: [
                "primary.webp",
                "https://media.merian.app/cdn/test.jpg"
            ],
            videoPaths: [
                localVideoURL.path,
                "https://media.merian.app/cdn/test.mp4",
                "https://example.com/unapproved.mp4"
            ],
            referenceImageURL:
                "https://media.merian.app/cdn/reference.jpg"
        )

        #expect(request.photoSources.count == 3)
        #expect(request.videoSources == [
            .local(localVideoURL),
            .approvedRemote(remoteVideoURL)
        ])
    }

    @Test("Single share orders primary and fallback references")
    func singleShareOrdersPrimaryAndFallbackReferences() throws {
        let primaryURL = try #require(URL(
            string: "https://media.merian.app/scans/primary.webp"
        ))
        let fallbackURL = try #require(URL(
            string: "https://media.merian.app/references/monarch.webp"
        ))
        let request = DiscoveryShareRequest.make(
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            liveImageData: nil,
            primaryImageReference:
                "https://media.merian.app/scans/primary.webp",
            fallbackImageReference:
                "https://media.merian.app/references/monarch.webp"
        )

        #expect(request.imageSources == [
            .approvedRemote(primaryURL),
            .approvedRemote(fallbackURL)
        ])
        #expect(request.message.contains("Monarch (Danaus plexippus)"))
    }

    @Test("Unapproved primary share reference falls back safely")
    func unapprovedPrimaryFallsBackSafely() throws {
        let fallbackURL = try #require(URL(
            string: "https://media.merian.app/references/safe.webp"
        ))
        let request = DiscoveryShareRequest.make(
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            liveImageData: nil,
            primaryImageReference: "https://example.com/private.webp",
            fallbackImageReference: fallbackURL.absoluteString
        )

        #expect(request.imageSources == [.approvedRemote(fallbackURL)])
    }

    @Test("Batch share treats an approved remote primary as primary")
    func batchShareUsesRemotePrimaryBeforeReference() throws {
        let primaryURL = try #require(URL(
            string: "https://media.merian.app/scans/cloud-primary.webp"
        ))
        let fallbackURL = try #require(URL(
            string: "https://media.merian.app/references/fallback.webp"
        ))
        let discovery = BatchDiscoveryShareRequest.Discovery(
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            primaryImageReference: primaryURL.absoluteString,
            fallbackImageReference: fallbackURL.absoluteString
        )

        #expect(discovery.imageSources == [
            .approvedRemote(primaryURL),
            .approvedRemote(fallbackURL)
        ])
        #expect(
            BatchDiscoveryShareRequest(discoveries: [discovery])
                .message.contains(PublicBrand.websiteURL.absoluteString)
        )
    }

    @Test("Batch share downsamples retained images to its memory bound")
    func batchShareDownsamplesRetainedImages() async throws {
        let sourceURL = try makeTemporaryJPEG(width: 1_600, height: 800)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let request = BatchDiscoveryShareRequest(discoveries: [
            .init(
                commonName: "Monarch",
                scientificName: "Danaus plexippus",
                primaryImageReference: sourceURL.path,
                fallbackImageReference: nil
            )
        ])

        let payload = await MediaExportService.live.prepareBatchShare(request)
        let images: [CGImage] = payload.items.compactMap { item -> CGImage? in
            guard case .image(let image) = item else { return nil }
            return image.image
        }
        let image = try #require(images.first)
        let largestDimension = max(image.width, image.height)

        #expect(
            largestDimension
                <= Int(MediaExportSizingPolicy.batchShareMaxPixelSize)
        )
        #expect(largestDimension > 0)
    }

    @Test("Save result reports mixed success without changing copy")
    func saveResultFormatsMixedMedia() {
        var result = MediaSaveResult()
        result.record(.photo, success: true)
        result.record(.video, success: true)
        result.record(.video, success: false)

        #expect(result.photosSaved == 1)
        #expect(result.videosSaved == 1)
        #expect(result.totalAttempted == 3)
        #expect(result.totalSaved == 2)
        #expect(result.hasFailures)
        #expect(
            result.successMessage
                == "Saved 1 photo and 1 video to your camera roll. Some items couldn't be saved."
        )
    }

    private func makeTemporaryJPEG(width: Int, height: Int) throws -> URL {
        let bytesPerRow = width * 4
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw CocoaError(.coderInvalidValue)
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.coderInvalidValue)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "media-export-bounds-\(UUID().uuidString).jpg"
        )
        try (data as Data).write(to: url, options: .atomic)
        return url
    }
}
