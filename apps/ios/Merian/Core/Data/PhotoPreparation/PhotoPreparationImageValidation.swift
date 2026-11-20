import Darwin
import Foundation
import ImageIO

// Bounded source-byte and header validation shared by picker transfer, P1 and inbox.
extension PhotoPreparationLockedFiles {
    static func boundedRead(fd: Int32, maximumBytes: Int64) throws -> Data {
        var info = stat()
        guard maximumBytes > 0, maximumBytes <= PhotoPreparationPolicy.original,
              fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size > 0, info.st_size <= maximumBytes else { throw PhotoPreparationFailure.sizeLimit }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            try Task.checkCancellation()
            let remaining = Int(maximumBytes) - data.count
            let count = Darwin.read(fd, &buffer, min(buffer.count, remaining + 1))
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw PhotoPreparationFailure.unavailable }
            if count == 0 { break }
            guard count <= remaining else { throw PhotoPreparationFailure.sizeLimit }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count == info.st_size else { throw PhotoPreparationFailure.inconsistentOwnership }
        return data
    }

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
