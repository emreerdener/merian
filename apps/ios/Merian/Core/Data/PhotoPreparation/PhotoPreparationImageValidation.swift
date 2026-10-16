import Foundation
import ImageIO

// Header validation shared by standalone P1 and the isolated inbox copy.
extension PhotoPreparationLockedFiles {
    static func validateImage(_ data: Data, maximumBytes: Int64) throws -> String {
        guard !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source) as String?,
              (CGImageSourceCopyTypeIdentifiers() as? [String] ?? []).contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.int64Value > 0, height.int64Value > 0 else { throw PhotoPreparationFailure.invalidMedia }
        let (pixels, overflow) = width.int64Value.multipliedReportingOverflow(by: height.int64Value)
        guard !overflow, pixels <= PhotoPreparationPolicy.maximumPixels else { throw PhotoPreparationFailure.sizeLimit }
        return type
    }

}
