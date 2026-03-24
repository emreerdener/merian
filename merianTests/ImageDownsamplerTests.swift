import XCTest
import UIKit
@testable import merian

final class ImageDownsamplerTests: XCTestCase {
    
    // Generates a massive 12MP synthetic mock exactly replicating a live iPhone Capture Buffer
    private func createMassiveMockImage() -> UIImage {
        let size = CGSize(width: 4000, height: 3000)
        let rect = CGRect(origin: .zero, size: size)
        
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        UIColor.red.setFill()
        UIRectFill(rect)
        let largeImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return largeImage
    }

    func testDownsamplerConstrainsBinaryMemoryBoundsNatively() async {
        // Arrange
        let largeImage = createMassiveMockImage()
        // Simulate extraction size of a 12MP uncompressed sensor byte array
        guard let data = largeImage.jpegData(compressionQuality: 1.0) else {
            XCTFail("Failed to allocate raw sensor bytes")
            return
        }
        
        // Ensure starting constraints
        XCTAssertGreaterThan(largeImage.size.width, 3000, "Starting buffer should be 12MP scale")
        
        // Act
        let expectedMaxSize: CGFloat = 800
        let downsampledCGImage = await ImageDownsampler.shared.downsample(data: data, maxSize: expectedMaxSize)
        
        // Assert
        XCTAssertNotNil(downsampledCGImage, "ImageDownsampler abruptly failed CGImage C-level mapping")
        
        let actualMaxDimension = max(downsampledCGImage!.width, downsampledCGImage!.height)
        XCTAssertLessThanOrEqual(CGFloat(actualMaxDimension), expectedMaxSize, "The downsampled image breached the strict Zero-OOM maxSize constraint")
    }
    
    func testDownsamplerConstrainsDiskURLBoundsNatively() async throws {
        // Arrange
        let largeImage = createMassiveMockImage()
        guard let data = largeImage.jpegData(compressionQuality: 1.0) else {
            XCTFail("Failed to allocate raw sensor bytes")
            return
        }
        
        // Natively write the fake 12MP payload to the sandbox disk
        let tempURL = URL.documentsDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try data.write(to: tempURL, options: .atomic)
        
        // Ensure cleanup occurs regardless of outcome
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Act
        let expectedMaxSize: CGFloat = 400
        let downsampledCGImage = await ImageDownsampler.shared.downsample(url: tempURL, maxSize: expectedMaxSize)
        
        // Assert
        XCTAssertNotNil(downsampledCGImage, "ImageDownsampler failed to parse physical .jpg URL securely")
        
        let actualMaxDimension = max(downsampledCGImage!.width, downsampledCGImage!.height)
        XCTAssertLessThanOrEqual(CGFloat(actualMaxDimension), expectedMaxSize, "The disk-driven CGImage breached OS compression bounds natively")
    }
}
