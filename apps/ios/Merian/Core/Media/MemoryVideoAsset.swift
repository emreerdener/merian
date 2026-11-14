import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// A bounded, private MP4 source. No file URL, temporary copy or network fallback.
/// AVFoundation invokes this delegate only on the explicitly configured main queue.
@MainActor
final class MemoryVideoAsset: NSObject, @preconcurrency AVAssetResourceLoaderDelegate {
    enum Failure: Error { case unavailable, invalidRange }
    static let maximumBytes = 12 * 1024 * 1024
    let asset: AVURLAsset
    private let address: URL
    private var bytes: Data?
    private let validate: () -> Bool
    var retainedByteCount: Int { bytes?.count ?? 0 }

    init(bytes: Data, validate: @escaping () -> Bool) throws {
        guard !bytes.isEmpty, bytes.count <= Self.maximumBytes, validate(),
              let address = URL(string: "merian-memory-video://original/" + UUID().uuidString + ".mp4") else {
            throw Failure.unavailable
        }
        self.bytes = bytes; self.validate = validate; self.address = address
        asset = AVURLAsset(url: address, options: [
            AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue
        ])
        super.init()
        asset.resourceLoader.setDelegate(self, queue: .main)
    }

    func close() {
        bytes = nil
        asset.cancelLoading()
    }

    /// Inclusive start/exclusive end; rejects arithmetic overflow and impossible offsets.
    static func range(count: Int, requestedOffset: Int64, currentOffset: Int64,
                      requestedLength: Int, toEnd: Bool) throws -> Range<Int> {
        guard count >= 0, requestedOffset >= 0, currentOffset >= 0, requestedLength >= 0,
              requestedOffset <= Int64(count), currentOffset <= Int64(count) else { throw Failure.invalidRange }
        let start = Int(max(requestedOffset, currentOffset))
        let end: Int
        if toEnd { end = count } else {
            let (requestedEnd, overflow) = Int(requestedOffset).addingReportingOverflow(requestedLength)
            guard !overflow else { throw Failure.invalidRange }
            end = min(count, requestedEnd)
        }
        guard start <= end else { throw Failure.invalidRange }
        return start..<end
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard request.request.url == address, validate(), let bytes else {
            if !request.isCancelled && !request.isFinished { request.finishLoading(with: Failure.unavailable) }
            close(); return true
        }
        if let info = request.contentInformationRequest {
            info.contentType = UTType.mpeg4Movie.identifier
            info.contentLength = Int64(bytes.count)
            info.isByteRangeAccessSupported = true
        }
        do {
            if let data = request.dataRequest {
                let range = try Self.range(count: bytes.count, requestedOffset: data.requestedOffset,
                    currentOffset: data.currentOffset, requestedLength: data.requestedLength,
                    toEnd: data.requestsAllDataToEndOfResource)
                // Bound each response copy; the immutable source remains a single retained Data.
                var offset = range.lowerBound
                while offset < range.upperBound {
                    guard !request.isCancelled else { return true }
                    let end = min(range.upperBound, offset + 256 * 1024)
                    data.respond(with: bytes.subdata(in: offset..<end)); offset = end
                }
            }
            request.finishLoading()
        } catch { request.finishLoading(with: error) }
        return true
    }
}
