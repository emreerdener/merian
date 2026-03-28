import Foundation
import Vision
import UIKit

/// Uses Apple Vision's objectness observation combined with LiDAR depth maps to generate 
/// physical boundary measurements without artificial reference points (like rulers).
actor SizeEstimator {
    
    /// Calculate physical subject size using LiDAR depth and normalized Vision bounding box.
    ///
    /// - Parameters:
    ///   - imageData: The captured image data
    ///   - distanceMeters: The physical distance from the camera to the primary foreground subject, computed via LiDAR
    /// - Returns: The estimated maximum linear dimension of the primary subject in centimeters
    static func estimateSize(imageData: Data, distanceMeters: Float) async -> Double? {
        return autoreleasepool {
            guard let cgImage = ImageDownsampler.shared.downsample(data: imageData, maxSize: 512) else { return nil }
        
            let request = VNGenerateObjectnessBasedSaliencyImageRequest()
            
            do {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([request])
            
            // 2. Find the most prominent object observation
            guard let observations = request.results,
                  let salientObservation = observations.first,
                  let salientObjects = salientObservation.salientObjects,
                  let activeObject = salientObjects.first else {
                return nil
            }
            
            let box = activeObject.boundingBox
            
            // 4. Calculate Plane Width based on standard iPhone wide lens FOV.
            // A typical iPhone main wide camera has roughly a 70-degree horizontal field of view.
            // Physical Plane Width = 2 * Distance * tan(FOV / 2)
            let fovRadians = 70.0 * .pi / 180.0
            let physicalPlaneWidthMeters = 2.0 * Double(distanceMeters) * tan(fovRadians / 2.0)
            
            // On a 4:3 sensor, physicalPlaneHeightMeters = physicalPlaneWidthMeters * (4.0/3.0)
            let physicalPlaneHeightMeters = physicalPlaneWidthMeters * (4.0 / 3.0)
            
            // Calculate absolute width and height mapping from the normalized box
            let subjectWidthMeters = Double(box.width) * physicalPlaneWidthMeters
            let subjectHeightMeters = Double(box.height) * physicalPlaneHeightMeters
            
            let maxSizeMeters = max(subjectWidthMeters, subjectHeightMeters)
            
            // Return size in centimeters
            return maxSizeMeters * 100.0
            } catch {
                return nil
            }
        }
    }
}
