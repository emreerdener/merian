import Testing
import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import Merian

@MainActor
struct ImageDownsamplerTests {
    
    // Simulates generating an extremely massive 12MP raw pixel array boundary in memory dynamically
    private func generateMassiveMemoryRawFootprint() -> Data {
        let width = 4000
        let height = 4000
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )
        
        guard let context = context, let cgImage = context.makeImage() else {
            fatalError("CRITICAL: Failed to construct raw CoreGraphics testing bounds natively.")
        }
        
        #if canImport(UIKit)
        let image = UIImage(cgImage: cgImage)
        guard let data = image.jpegData(compressionQuality: 1.0) else {
            fatalError("Failed to serialize massive physical JPEG payload")
        }
        return data
        #else
        return Data() // Fallback compilation
        #endif
    }
    
    @Test func testImageDownsamplerConstrainsMassivePayloadsToSafeMemoryLimits() async throws {
        // Arrange
        let massiveDataBuffer = generateMassiveMemoryRawFootprint()
        let requestedSafeMaxDimension: CGFloat = 300.0
        
        // Act: Funnel the 4000x4000 raw Data footprint securely through our explicit native decoupling boundary
        let downsampledCGImage = await ImageDownsampler.shared.downsample(data: massiveDataBuffer, maxSize: requestedSafeMaxDimension)
        
        // Assert: Ensure it did not crash natively and securely returned the CF object
        #expect(downsampledCGImage != nil, "ImageDownsampler MUST extract the raw CGImage without dropping bounds unexpectedly")
        
        if let safeImage = downsampledCGImage {
            let width = CGFloat(safeImage.width)
            let height = CGFloat(safeImage.height)
            
            // Assert: The absolute largest dimension MUST NEVER exceed 300.0 natively preventing OOM execution
            let largestDimension = max(width, height)
            
            #expect(largestDimension <= requestedSafeMaxDimension, "CRITICAL MEMORY FAILURE: Downsampled boundary escaped the physical 300px limits!")
            #expect(largestDimension > 0, "Downsampled boundary MUST inherently contain physical dimension sizing")
        }
    }
}
