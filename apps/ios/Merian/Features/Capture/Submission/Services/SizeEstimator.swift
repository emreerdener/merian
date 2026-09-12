import Foundation
import Vision

/// Uses Apple Vision's objectness observation combined with LiDAR depth maps to generate
/// physical boundary measurements without artificial reference points (like rulers).
enum SizeEstimator {

    /// Calculate physical subject size using LiDAR depth and normalized Vision bounding box.
    ///
    /// - Parameters:
    ///   - imageData: The captured image data
    ///   - distanceMeters: The physical distance from the camera to the primary foreground subject, computed via LiDAR
    /// - Returns: The estimated maximum linear dimension of the primary subject in centimeters
    static func estimateSize(imageData: Data, distanceMeters: Float) async -> Double? {
        autoreleasepool {
            guard let cgImage = ImageDownsampler.downsample(data: imageData, maxSize: 512) else { return nil }

            let request = VNGenerateObjectnessBasedSaliencyImageRequest()

            do {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([request])

                guard let salientObservation = request.results?.first,
                      let activeObject = salientObservation.salientObjects?.first else {
                    return nil
                }

                let box = activeObject.boundingBox
                // The main wide camera is modeled with the existing 70-degree
                // horizontal field of view and a 4:3 sensor.
                let fovRadians = 70.0 * .pi / 180.0
                let physicalPlaneWidthMeters = 2.0
                    * Double(distanceMeters)
                    * tan(fovRadians / 2.0)
                let physicalPlaneHeightMeters = physicalPlaneWidthMeters
                    * (4.0 / 3.0)
                let subjectWidthMeters = Double(box.width)
                    * physicalPlaneWidthMeters
                let subjectHeightMeters = Double(box.height)
                    * physicalPlaneHeightMeters

                return max(subjectWidthMeters, subjectHeightMeters) * 100.0
            } catch {
                return nil
            }
        }
    }
}
