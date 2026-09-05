import SwiftUI
import UIKit
import XCTest

@testable import Merian

@MainActor
final class ExploreMediaLayoutTests: XCTestCase {
    private func makeMediaItem(
        kind: ExploreMediaKind,
        url: String,
        orderIndex: Int
    ) -> ExploreMediaItem {
        ExploreMediaItem(
            kind: kind,
            url: url,
            thumbnailUrl: kind == .image ? url : "\(url)-poster",
            orderIndex: orderIndex,
            durationSeconds: kind == .image ? nil : 4,
            hasAudio: kind != .image
        )
    }

    private func makeStripedImage(
        size: CGSize,
        topColor: UIColor,
        bottomColor: UIColor
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            topColor.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.5))

            bottomColor.setFill()
            context.fill(CGRect(x: 0, y: size.height * 0.5, width: size.width, height: size.height * 0.5))
        }
    }

    private func render<V: View>(_ view: V, width: CGFloat = 320) -> UIImage {
        let fittingSize = CGSize(width: width, height: width)
        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: view.frame(width: width, height: width))
            renderer.scale = 1
            if let image = renderer.uiImage {
                return image
            }
        }

        let controller = UIHostingController(rootView: view.frame(width: width, height: width))
        controller.view.bounds = CGRect(origin: .zero, size: fittingSize)
        controller.view.frame = CGRect(origin: .zero, size: fittingSize)
        controller.view.backgroundColor = .clear

        let window = UIWindow(frame: controller.view.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()

        controller.view.setNeedsLayout()
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: fittingSize, format: format).image { context in
            controller.view.layer.render(in: context.cgContext)
        }

        window.isHidden = true
        return image
    }

    private struct RGBAPixel {
        let r: UInt8
        let g: UInt8
        let b: UInt8
        let a: UInt8
    }

    private func rgbaPixel(in image: UIImage, x: Int, y: Int) -> RGBAPixel {
        guard let cgImage = image.cgImage,
              let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
            XCTFail("Failed to crop pixel from rendered image")
            return RGBAPixel(r: 0, g: 0, b: 0, a: 0)
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            XCTFail("Failed to create pixel sampling context")
            return RGBAPixel(r: 0, g: 0, b: 0, a: 0)
        }

        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return RGBAPixel(r: pixel[0], g: pixel[1], b: pixel[2], a: pixel[3])
    }

    private func assertPixel(
        _ pixel: RGBAPixel,
        approximately color: UIColor,
        tolerance: Int = 28,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha), file: file, line: line)

        XCTAssertGreaterThanOrEqual(Int(pixel.a), 245, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(Int(pixel.r) - Int(red * 255)), tolerance, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(Int(pixel.g) - Int(green * 255)), tolerance, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(Int(pixel.b) - Int(blue * 255)), tolerance, file: file, line: line)
    }

    func testCarouselKeepsEveryMediaTypeInAuthoredOrder() {
        let image = makeMediaItem(
            kind: .image,
            url: "https://example.com/image.jpg",
            orderIndex: 2
        )
        let video = makeMediaItem(
            kind: .video,
            url: "https://example.com/video.mp4",
            orderIndex: 1
        )
        let audio = makeMediaItem(
            kind: .audio,
            url: "https://example.com/audio.wav",
            orderIndex: 0
        )

        let orderedItems = ExplorePostMediaCarouselPolicy.orderedItems(
            [image, audio, video],
            fallbackImageUrl: "https://example.com/fallback.jpg"
        )

        XCTAssertEqual(orderedItems, [audio, video, image])
    }

    func testCarouselUsesLegacyImageOnlyWhenMediaItemsAreUnavailable() {
        let fallbackUrl = "https://example.com/fallback.jpg"

        XCTAssertEqual(
            ExplorePostMediaCarouselPolicy.orderedItems(
                nil,
                fallbackImageUrl: fallbackUrl
            ),
            [.legacyImage(url: fallbackUrl)]
        )
        XCTAssertEqual(
            ExplorePostMediaCarouselPolicy.orderedItems(
                [],
                fallbackImageUrl: fallbackUrl
            ),
            [.legacyImage(url: fallbackUrl)]
        )
    }

    func testCarouselPreservesSelectedMediaIdentityWhenOrderMetadataChanges() {
        let image = makeMediaItem(
            kind: .image,
            url: "https://example.com/image.jpg",
            orderIndex: 0
        )
        let video = makeMediaItem(
            kind: .video,
            url: "https://example.com/video.mp4",
            orderIndex: 1
        )
        let reorderedVideo = makeMediaItem(
            kind: .video,
            url: video.url,
            orderIndex: 0
        )
        let reorderedImage = makeMediaItem(
            kind: .image,
            url: image.url,
            orderIndex: 1
        )
        let namespace = "post-cover"
        let previousPages = ExplorePostMediaCarouselPolicy.pages(
            for: [image, video],
            namespace: namespace
        )
        let updatedPages = ExplorePostMediaCarouselPolicy.pages(
            for: [reorderedVideo, reorderedImage],
            namespace: namespace
        )

        XCTAssertEqual(
            ExplorePostMediaCarouselPolicy.reconciledSelectedPageID(
                currentID: previousPages[1].id,
                previousPages: previousPages,
                updatedPages: updatedPages
            ),
            updatedPages[0].id
        )
    }

    func testCarouselFallsBackToCoverWhenSelectionIsRemoved() {
        let image = makeMediaItem(
            kind: .image,
            url: "https://example.com/image.jpg",
            orderIndex: 0
        )
        let video = makeMediaItem(
            kind: .video,
            url: "https://example.com/video.mp4",
            orderIndex: 1
        )
        let previousPages = ExplorePostMediaCarouselPolicy.pages(
            for: [image, video],
            namespace: "post-cover"
        )
        let updatedPages = ExplorePostMediaCarouselPolicy.pages(
            for: [image],
            namespace: "post-cover"
        )

        XCTAssertEqual(
            ExplorePostMediaCarouselPolicy.reconciledSelectedPageID(
                currentID: previousPages[1].id,
                previousPages: previousPages,
                updatedPages: updatedPages
            ),
            updatedPages[0].id
        )
    }

    func testCarouselResetsToCoverForANewPostIdentity() {
        let image = makeMediaItem(
            kind: .image,
            url: "https://example.com/image.jpg",
            orderIndex: 0
        )
        let video = makeMediaItem(
            kind: .video,
            url: "https://example.com/video.mp4",
            orderIndex: 1
        )
        let previousPages = ExplorePostMediaCarouselPolicy.pages(
            for: [image, video],
            namespace: "post-1"
        )
        let updatedPages = ExplorePostMediaCarouselPolicy.pages(
            for: [image, video],
            namespace: "post-2"
        )

        XCTAssertEqual(
            ExplorePostMediaCarouselPolicy.reconciledSelectedPageID(
                currentID: previousPages[1].id,
                previousPages: previousPages,
                updatedPages: updatedPages
            ),
            updatedPages[0].id
        )
    }

    func testCarouselAssignsDistinctIdentityToRepeatedMediaURLs() {
        let firstAudio = makeMediaItem(
            kind: .audio,
            url: "https://example.com/repeated.wav",
            orderIndex: 0
        )
        let secondAudio = makeMediaItem(
            kind: .audio,
            url: "https://example.com/repeated.wav",
            orderIndex: 1
        )
        let pages = ExplorePostMediaCarouselPolicy.pages(
            for: [firstAudio, secondAudio],
            namespace: "post-cover"
        )

        XCTAssertEqual(Set(pages.map(\.id)).count, 2)
        XCTAssertEqual(pages.map(\.id.occurrence), [0, 1])
    }

    func testMultiItemCarouselReservesHorizontalDragForPaging() {
        XCTAssertEqual(
            ExplorePostMediaCarouselPolicy.detailAudioSeekingMode(
                mediaItemCount: 1
            ),
            .fullSpectrogram
        )
        XCTAssertEqual(
            ExplorePostMediaCarouselPolicy.detailAudioSeekingMode(
                mediaItemCount: 2
            ),
            .playmarkerOnly
        )
    }

    func testOnlyPrimaryStandaloneAudioReceivesBoostControls() {
        let audio = makeMediaItem(
            kind: .audio,
            url: "https://example.com/audio.wav",
            orderIndex: 0
        )
        let image = makeMediaItem(
            kind: .image,
            url: "https://example.com/image.jpg",
            orderIndex: 1
        )

        XCTAssertTrue(
            ExplorePostMediaCarouselPolicy.allowsAudioBoost(
                mediaItem: audio,
                index: 0
            )
        )
        XCTAssertFalse(
            ExplorePostMediaCarouselPolicy.allowsAudioBoost(
                mediaItem: audio,
                index: 1
            )
        )
        XCTAssertFalse(
            ExplorePostMediaCarouselPolicy.allowsAudioBoost(
                mediaItem: image,
                index: 0
            )
        )
    }

    func testPrimaryStandaloneAudioDetectionUsesAuthoredOrder() {
        let laterImage = makeMediaItem(
            kind: .image,
            url: "https://example.com/image.jpg",
            orderIndex: 1
        )
        let primaryAudio = makeMediaItem(
            kind: .audio,
            url: "https://example.com/audio.wav",
            orderIndex: 0
        )
        let primaryImage = makeMediaItem(
            kind: .image,
            url: "https://example.com/cover.jpg",
            orderIndex: 0
        )
        let laterAudio = makeMediaItem(
            kind: .audio,
            url: "https://example.com/later-audio.wav",
            orderIndex: 1
        )

        XCTAssertTrue(
            ExplorePostMediaCarouselPolicy.hasPrimaryStandaloneAudio(
                [laterImage, primaryAudio],
                fallbackImageUrl: laterImage.url
            )
        )
        XCTAssertFalse(
            ExplorePostMediaCarouselPolicy.hasPrimaryStandaloneAudio(
                [laterAudio, primaryImage],
                fallbackImageUrl: primaryImage.url
            )
        )
    }

    func testPlayerResetCancelsAnInFlightAudioSeek() {
        let state = ExplorePublicMediaPlaybackState()
        state.beginAudioSeek(wasPlaying: true)

        state.resetPlayerState()

        XCTAssertFalse(state.isAudioSeeking)
        XCTAssertFalse(state.finishAudioSeek())
    }

    func testExploreFeedMediaViewLandscapeImageFillsSquare() {
        let topColor = UIColor.systemTeal
        let bottomColor = UIColor.systemOrange
        let image = makeStripedImage(
            size: CGSize(width: 1200, height: 800),
            topColor: topColor,
            bottomColor: bottomColor
        )

        let rendered = render(
            ExploreFeedMediaView(
                postId: "preview-landscape",
                imageUrl: "preview-landscape",
                reloadGeneration: 0,
                preloadedImage: image
            )
        )

        XCTAssertEqual(rendered.size.width, 320, accuracy: 1)
        XCTAssertEqual(rendered.size.height, 320, accuracy: 1)

        assertPixel(rgbaPixel(in: rendered, x: 160, y: 8), approximately: topColor)
        assertPixel(rgbaPixel(in: rendered, x: 160, y: 311), approximately: bottomColor)
    }

    func testExploreFeedMediaViewPortraitImageFillsSquare() {
        let topColor = UIColor.systemPink
        let bottomColor = UIColor.systemIndigo
        let image = makeStripedImage(
            size: CGSize(width: 800, height: 1200),
            topColor: topColor,
            bottomColor: bottomColor
        )

        let rendered = render(
            ExploreFeedMediaView(
                postId: "preview-portrait",
                imageUrl: "preview-portrait",
                reloadGeneration: 0,
                preloadedImage: image
            )
        )

        XCTAssertEqual(rendered.size.width, 320, accuracy: 1)
        XCTAssertEqual(rendered.size.height, 320, accuracy: 1)

        assertPixel(rgbaPixel(in: rendered, x: 160, y: 8), approximately: topColor)
        assertPixel(rgbaPixel(in: rendered, x: 160, y: 311), approximately: bottomColor)
    }

    func testExploreDetailMediaViewLandscapeImageFillsSquare() {
        let topColor = UIColor.systemGreen
        let bottomColor = UIColor.systemBlue
        let image = makeStripedImage(
            size: CGSize(width: 1200, height: 800),
            topColor: topColor,
            bottomColor: bottomColor
        )

        let rendered = render(
            ExploreDetailMediaView(
                postId: "preview-detail",
                imageUrl: "preview-detail",
                reloadGeneration: 0,
                preloadedImage: image,
                allowsZoom: false
            )
        )

        XCTAssertEqual(rendered.size.width, 320, accuracy: 1)
        XCTAssertEqual(rendered.size.height, 320, accuracy: 1)

        assertPixel(rgbaPixel(in: rendered, x: 160, y: 24), approximately: topColor)
        assertPixel(rgbaPixel(in: rendered, x: 160, y: 295), approximately: bottomColor)
    }
}
