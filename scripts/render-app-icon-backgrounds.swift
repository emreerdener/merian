// Mechanical export only: composite the supplied pixels without redrawing them.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: render-app-icon-backgrounds.swift SOURCE OUTPUT_DIRECTORY")
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width == 1024, image.height == 1024,
      let space = CGColorSpace(name: CGColorSpace.sRGB) else {
    fatalError("Expected a readable 1024 x 1024 source image")
}

for (name, white) in [("default", CGFloat(1)), ("tinted", CGFloat(0))] {
    guard let context = CGContext(
        data: nil, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("Cannot create opaque export context") }
    let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    context.setFillColor(red: white, green: white, blue: white, alpha: 1)
    context.fill(bounds)
    context.draw(image, in: bounds)
    guard let result = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            outputURL.appendingPathComponent("\(name).png") as CFURL,
            UTType.png.identifier as CFString, 1, nil
          ) else { fatalError("Cannot create PNG destination") }
    CGImageDestinationAddImage(destination, result, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Cannot write \(name) export")
    }
}
