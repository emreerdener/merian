import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Temporary five-frame cohort. Retaining it also retains the exact source lease.
/// No transfer API exists until complete video/audio cohort staging is implemented.
actor ObservationVideoFrameDerivation {
    nonisolated let source: ObservationVideoProvenance.Artifact
    nonisolated let parameters: ObservationVideoProvenance.Parameters
    nonisolated let frames: [ObservationVideoProvenance.Frame]
    nonisolated let files: [URL]
    private let sourceLease: ObservationRetainedVideoUse
    private let directory: URL

    init(source: ObservationVideoProvenance.Artifact, parameters: ObservationVideoProvenance.Parameters,
         frames: [ObservationVideoProvenance.Frame], files: [URL], sourceLease: ObservationRetainedVideoUse, directory: URL) {
        self.source = source; self.parameters = parameters; self.frames = frames; self.files = files
        self.sourceLease = sourceLease; self.directory = directory
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

enum ObservationVideoFrameError: Error {
    case busy, invalidParameters, invalidSource, invalidFrame, sourceChanged, timedOut
}

/// Inert producer: exact retained source -> transformed/cropped/resized single-encode frames.
actor ObservationVideoFrameDeriver {
    private var occupied = false
    private let validateAfterFrame: @Sendable (Int) async throws -> Void

    init(validateAfterFrame: @escaping @Sendable (Int) async throws -> Void = { _ in }) {
        self.validateAfterFrame = validateAfterFrame
    }

    func derive(source: ObservationRetainedVideoClip, sourceMediaID: UUID, directory: URL,
                cropCenterBasisPoints: Int, inferenceLongEdge: Int) async throws -> ObservationVideoFrameDerivation {
        guard !occupied else { throw ObservationVideoFrameError.busy }
        guard (0...10000).contains(cropCenterBasisPoints), [768, 1024].contains(inferenceLongEdge), directory.isFileURL else {
            throw ObservationVideoFrameError.invalidParameters
        }
        try Task.checkCancellation()
        occupied = true
        defer { occupied = false }
        let use = try await source.beginDerivation()
        try Task.checkCancellation()
        let validate = validateAfterFrame
        let worker = Task.detached(priority: .utility) {
            try await Self.prepare(source: use, sourceMediaID: sourceMediaID, directory: directory,
                                   cropCenterBasisPoints: cropCenterBasisPoints, inferenceLongEdge: inferenceLongEdge, validate: validate)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
    }

    private nonisolated static func prepare(
        source: ObservationRetainedVideoUse, sourceMediaID: UUID, directory: URL,
        cropCenterBasisPoints: Int, inferenceLongEdge: Int, validate: @Sendable (Int) async throws -> Void
    ) async throws -> ObservationVideoFrameDerivation {
        try Task.checkCancellation()
        let artifact = try sourceArtifact(source.url, id: sourceMediaID)
        let asset = AVURLAsset(url: source.url, options: [AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue])
        let duration = try await asset.load(.duration)
        guard duration.isNumeric, duration.seconds >= 0.1, duration.seconds <= 5 else { throw ObservationVideoFrameError.invalidSource }
        let durationTicks = Int(CMTimeConvertScale(duration, timescale: 600, method: .roundHalfAwayFromZero).value)
        guard (60...3000).contains(durationTicks) else { throw ObservationVideoFrameError.invalidSource }
        let parameters = ObservationVideoProvenance.Parameters(durationTicks: durationTicks,
                                                               cropCenterBasisPoints: cropCenterBasisPoints, inferenceLongEdge: inferenceLongEdge)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let owned = directory.appendingPathComponent("video-frames-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: false)
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: owned) } }
        let decoder = ObservationVideoFrameDecoder(asset: asset)
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            await decoder.cancel()
        }
        let deadline = ContinuousClock.now + .seconds(30)
        do {
            let result = try await withTaskCancellationHandler {
                var frames: [ObservationVideoProvenance.Frame] = []
                var files: [URL] = []
                var totalBytes = 0
                var previousTime = 0
                for index in 0..<5 {
                    try Task.checkCancellation()
                    guard ContinuousClock.now < deadline else { throw ObservationVideoFrameError.timedOut }
                    let requested = min(max((durationTicks * (1 + 2 * index) + 5) / 10, 30), durationTicks - 30)
                    let sample = try await decoder.sample(ticks: requested, cropCenterBasisPoints: cropCenterBasisPoints, edge: inferenceLongEdge)
                    try Task.checkCancellation()
                    guard sample.actualTicks >= previousTime, sample.actualTicks < durationTicks,
                          !sample.bytes.isEmpty, sample.bytes.count <= 5_242_880 - totalBytes else { throw ObservationVideoFrameError.invalidFrame }
                    previousTime = sample.actualTicks
                    totalBytes += sample.bytes.count
                    let id = UUID()
                    let output = owned.appendingPathComponent("\(id.uuidString.lowercased()).\(sample.contentType == "image/webp" ? "webp" : "jpg")")
                    try sample.bytes.write(to: output, options: .atomic)
                    frames.append(.init(index: index, sourceMediaID: sourceMediaID, requestedTimeTicks: requested,
                                        actualTimeTicks: sample.actualTicks, artifact: .init(mediaID: id, contentType: sample.contentType,
                                                                                         byteCount: sample.bytes.count, sha256: hash(sample.bytes))))
                    files.append(output)
                    try await validate(index)
                }
                guard ContinuousClock.now < deadline else { throw ObservationVideoFrameError.timedOut }
                guard try sourceArtifact(source.url, id: sourceMediaID) == artifact else { throw ObservationVideoFrameError.sourceChanged }
                return ObservationVideoFrameDerivation(source: artifact, parameters: parameters, frames: frames, files: files,
                                                       sourceLease: source, directory: owned)
            } onCancel: { Task { await decoder.cancel() } }
            timeout.cancel()
            await timeout.value
            await decoder.cancel()
            try Task.checkCancellation()
            complete = true
            return result
        } catch {
            timeout.cancel()
            await timeout.value
            await decoder.cancel()
            throw error
        }
    }

    private nonisolated static func sourceArtifact(_ url: URL, id: UUID) throws -> ObservationVideoProvenance.Artifact {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, (1...12_582_912).contains(size.intValue) else { throw ObservationVideoFrameError.invalidSource }
        let bytes = try Data(contentsOf: url)
        guard bytes.count == size.intValue else { throw ObservationVideoFrameError.sourceChanged }
        return .init(mediaID: id, contentType: "video/mp4", byteCount: bytes.count, sha256: hash(bytes))
    }

    private nonisolated static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// AVFoundation objects and decoded pixels stay on this private actor. Only bytes/timing leave it.
private actor ObservationVideoFrameDecoder {
    struct Sample: Sendable {
        let bytes: Data
        let contentType: String
        let actualTicks: Int
    }
    private let generator: AVAssetImageGenerator
    private var cancelled = false

    init(asset: AVAsset) {
        generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 2048, height: 2048)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
    }

    func cancel() {
        cancelled = true
        generator.cancelAllCGImageGeneration()
    }

    func sample(ticks: Int, cropCenterBasisPoints: Int, edge: Int) async throws -> Sample {
        guard !cancelled else { throw CancellationError() }
        let result = try await generator.image(at: CMTime(value: Int64(ticks), timescale: 600))
        try Task.checkCancellation()
        guard !cancelled, result.actualTime.isNumeric else { throw CancellationError() }
        return try autoreleasepool {
            guard let cropped = ImageCropProcessor.squareCrop(result.image, verticalCenterFraction: CGFloat(cropCenterBasisPoints) / 10000),
                  let context = CGContext(data: nil, width: edge, height: edge, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw ObservationVideoFrameError.invalidFrame
            }
            context.interpolationQuality = .high
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: edge, height: edge))
            guard let resized = context.makeImage(),
                  let bytes = ImageCropProcessor.encode(resized, quality: 0.85), !bytes.isEmpty,
                  bytes.count <= 5_242_880,
                  let image = CGImageSourceCreateWithData(bytes as CFData, nil), let type = CGImageSourceGetType(image) else {
                throw ObservationVideoFrameError.invalidFrame
            }
            let identifier = type as String
            guard identifier == UTType.webP.identifier || identifier == UTType.jpeg.identifier else { throw ObservationVideoFrameError.invalidFrame }
            let actual = CMTimeConvertScale(result.actualTime, timescale: 600, method: .roundHalfAwayFromZero)
            return Sample(bytes: bytes, contentType: identifier == UTType.webP.identifier ? "image/webp" : "image/jpeg", actualTicks: Int(actual.value))
        }
    }
}
