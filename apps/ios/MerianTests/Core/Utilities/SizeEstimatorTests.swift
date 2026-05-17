import Testing
import Foundation
@testable import Merian

struct SizeEstimatorTests {
    
    @Test func testEstimateSizeGracefullyFailsWithNilOnCorruptedData() async {
        // Arrange
        let brokenData = "not an image".data(using: .utf8)!
        let distance: Float = 1.5 // 1.5 meters away
        
        // Act
        let sizeInCm = await SizeEstimator.estimateSize(imageData: brokenData, distanceMeters: distance)
        
        // Assert
        // ImageDownsampler rejects the raw ascii bytes into nil before Vision is even hit
        #expect(sizeInCm == nil, "A corrupt or non-readable image byte array must gracefully return nil instead of throwing.")
    }
    
    @Test func testEstimateSizeGracefullyFailsOnEmptyData() async {
        let emptyData = Data()
        let distance: Float = 1.0
        
        let sizeInCm = await SizeEstimator.estimateSize(imageData: emptyData, distanceMeters: distance)
        
        #expect(sizeInCm == nil)
    }
}
