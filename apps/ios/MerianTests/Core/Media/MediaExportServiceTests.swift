import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import UIKit

@testable import Merian

@Suite("Media export service")
struct MediaExportServiceTests {
    @Test("File requests preserve every approved URL in a persisted reference")
    func fileRequestsPreserveMultipleSources() throws {
        let paths = "https://media.merian.app/a.m4a,https://media.merian.app/b.m4a"
        let requests = MediaShareFileRequest.make(audioPaths: [paths], videoPaths: [])
        #expect(requests.count == 2)
        #expect(requests.map(\.source) == MediaExportSourceResolver.sources(from: paths).map(Optional.some))
    }

    @Test("Video export copies preserve the clip bytes and extension")
    func videoShareIncludesClip() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        // The export layer copies bytes; decoding validity belongs to capture.
        let bytes = Data([0, 0, 0, 20, 102, 116, 121, 112, 105, 115, 111, 109, 0, 0, 0, 0, 105, 115, 111, 109])
        try bytes.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let request = DiscoveryShareRequest.make(
            commonName: "Test", scientificName: "Test species", liveImageData: nil,
            primaryImageReference: nil, fallbackImageReference: nil, videoPaths: [source.path]
        )
        let payload = await MediaExportService.live.prepareShare(request)
        let files = payload.items.compactMap { item -> MediaShareFile? in
            guard case .file(let file) = item else { return nil }
            return file
        }
        #expect(!payload.hasUnavailableMedia)
        #expect(files.count == 1)
        let file = try #require(files.first)
        #expect(file.url.pathExtension == "mp4")
        #expect(try Data(contentsOf: file.url) == bytes)
    }

    @Test("Oversized recordings and mixed-success shares report unavailable media")
    func oversizedAndMixedMediaFailExplicitly() async throws {
        let source = try makeTemporaryAudio()
        defer { try? FileManager.default.removeItem(at: source) }
        let request = DiscoveryShareRequest.make(
            commonName: "Test", scientificName: "Test species", liveImageData: nil,
            primaryImageReference: nil, fallbackImageReference: nil,
            audioPaths: [source.path, "missing-recording.m4a"]
        )
        let mixed = await MediaExportService.live.prepareShare(request)
        #expect(mixed.hasUnavailableMedia)
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(ScanMediaPayloadPolicy.maxInferenceAudioBytes + 1))
        try handle.close()
        #expect(throws: (any Error).self) {
            try MediaShareFile(copying: source, kind: .audio, index: 1)
        }
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("Description-only scans intentionally share their summary without media")
    func descriptionOnlySharesSummary() async {
        let request = DiscoveryShareRequest.make(
            commonName: "Test", scientificName: "Test species", liveImageData: nil,
            primaryImageReference: nil, fallbackImageReference: nil,
            summary: .init(reasoning: "An identification based on the description.")
        )
        let payload = await MediaExportService.live.prepareShare(request)
        #expect(!payload.hasUnavailableMedia)
        #expect(payload.items.count == 1)
        guard case .text(let text) = payload.items.first else {
            Issue.record("Description-only share must contain the scan summary")
            return
        }
        #expect(text.contains("An identification based on the description."))
    }

    @Test("Audio-only shares include the recording and the AI summary")
    func audioShareIncludesRecordingAndSummary() async throws {
        let source = try makeTemporaryAudio()
        defer { try? FileManager.default.removeItem(at: source) }
        let request = DiscoveryShareRequest.make(
            commonName: "Test bird", scientificName: "Test species",
            liveImageData: nil, primaryImageReference: nil, fallbackImageReference: nil,
            audioPaths: [source.path],
            summary: .init(reasoning: "A repeating call is audible.", confidence: 0.93,
                           scanDate: Date(timeIntervalSince1970: 0))
        )
        let payload = await MediaExportService.live.prepareShare(request)
        let file = try #require(payload.items.compactMap { item -> MediaShareFile? in
            guard case .file(let file) = item else { return nil }
            return file
        }.first)
        #expect(!payload.hasUnavailableMedia)
        #expect(file.url != source)
        #expect(file.url.pathExtension == "wav")
        #expect(try Data(contentsOf: file.url) == Data(contentsOf: source))
        #expect(request.message.contains("AI identification reasoning:\nA repeating call is audible."))
        #expect(request.message.contains("AI confidence: 93%"))
        #expect(request.message.contains("Scan date:"))
        #expect(!request.message.contains("https://"))
    }

    @MainActor
    @Test("Activity items retain export copies and never delete source recordings")
    func activityItemsOwnTemporaryFiles() throws {
        let original = try makeTemporaryAudio()
        defer { try? FileManager.default.removeItem(at: original) }
        let url = try autoreleasepool {
            var file: MediaShareFile? = try MediaShareFile(copying: original, kind: .audio, index: 1)
            let url = try #require(file?.url)
            var payload: MediaSharePayload? = MediaSharePayload(items: [.file(try #require(file))])
            let source = try #require(
                payload?.activityItems.first as? MediaShareFileItemSource
            )
            payload = nil
            file = nil
            #expect(FileManager.default.fileExists(atPath: url.path))
            let controller = UIActivityViewController(activityItems: [], applicationActivities: nil)
            for activity in [UIActivity.ActivityType.airDrop, .message, .mail, .copyToPasteboard] {
                #expect(source.activityViewController(controller, itemForActivityType: activity) as? URL == url)
            }
            return url
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: original.path))
    }

    @Test("Missing and unapproved recordings fail instead of silently sharing text alone")
    func unavailableAudioIsExplicit() async {
        for path in ["missing-share-recording.m4a", "https://example.com/private.m4a"] {
            let request = DiscoveryShareRequest.make(
                commonName: "Test bird", scientificName: "Test species",
                liveImageData: nil, primaryImageReference: nil, fallbackImageReference: nil,
                audioPaths: [path]
            )
            let payload = await MediaExportService.live.prepareShare(request)
            #expect(payload.hasUnavailableMedia)
        }
    }

    @Test("Batch audio shares preserve every discovery summary and recording")
    func batchAudioShare() async throws {
        let source = try makeTemporaryAudio()
        defer { try? FileManager.default.removeItem(at: source) }
        let request = BatchDiscoveryShareRequest(discoveries: (1...2).map { index in
            .init(commonName: "Bird \(index)", scientificName: "Test species",
                  primaryImageReference: nil, fallbackImageReference: nil,
                  audioPaths: [source.path], summary: .init(reasoning: "Reasoning \(index)"))
        })
        let payload = await MediaExportService.live.prepareBatchShare(request)
        let files = payload.items.compactMap { item -> MediaShareFile? in
            guard case .file(let file) = item else { return nil }
            return file
        }
        #expect(!payload.hasUnavailableMedia)
        #expect(files.count == 2)
        #expect(Set(files.map { $0.url.lastPathComponent }).count == 2)
        #expect(request.message.contains("Reasoning 1"))
        #expect(request.message.contains("Reasoning 2"))
    }

    @Test("Invalid confidence and blank reasoning stay out of summaries")
    func summaryOmitsInvalidFields() {
        for confidence in [Double.nan, .infinity, -0.1, 1.1] {
            let text = DiscoveryShareSummary(reasoning: "  ", confidence: confidence)
                .text(commonName: "Test", scientificName: "Test species")
            #expect(!text.contains("AI confidence"))
            #expect(!text.contains("AI identification reasoning"))
            #expect(!text.contains("Scan date"))
        }
    }

    private func makeTemporaryAudio() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        // One silent 8-bit PCM sample, with a complete RIFF/WAVE header.
        let bytes: [UInt8] = [82,73,70,70,38,0,0,0,87,65,86,69,102,109,116,32,
                             16,0,0,0,1,0,1,0,64,31,0,0,64,31,0,0,1,0,8,0,
                             100,97,116,97,2,0,0,0,128,128]
        try Data(bytes).write(to: url)
        return url
    }

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
                .message.contains("Monarch (Danaus plexippus)")
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
