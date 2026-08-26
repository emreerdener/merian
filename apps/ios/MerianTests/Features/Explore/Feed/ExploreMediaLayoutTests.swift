import SwiftUI
import UIKit
import XCTest

@testable import Merian

@MainActor
final class ExploreMediaLayoutTests: XCTestCase {
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
