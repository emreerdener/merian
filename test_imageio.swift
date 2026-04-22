import Foundation
import CoreGraphics
import ImageIO
import AppKit

// 1. Create a minimal JPEG
let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let jpegData = rep.representation(using: .jpeg, properties: [:])!

// 2. Save it as .webp
let url = URL(fileURLWithPath: "/tmp/test.webp")
try! jpegData.write(to: url)

// 3. Try to decode it
let options: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: 1024,
    kCGImageSourceShouldCache: false
]

if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
    if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
        print("SUCCESS! Width: \(image.width)")
    } else {
        print("FAILED to create thumbnail!")
    }
} else {
    print("FAILED to create source!")
}
