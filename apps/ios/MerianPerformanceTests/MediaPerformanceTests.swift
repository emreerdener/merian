import CryptoKit
import Foundation
@testable import Merian
import UIKit
import XCTest

@MainActor
final class MediaPerformanceTests: XCTestCase {
    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        return options
    }

    func testRepeatedBoundedImageDecode() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4_032, height: 3_024), format: format)
        let data = renderer.jpegData(withCompressionQuality: 0.85) { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4_032, height: 3_024))
        }
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            // Repeated real ImageIO work with a bounded lifetime, not a cache-hit benchmark.
            for _ in 0..<20 {
                autoreleasepool {
                    let image = ImageDownsampler.downsample(data: data, maxSize: 512)
                    XCTAssertNotNil(image)
                    XCTAssertLessThanOrEqual(max(image?.width ?? 0, image?.height ?? 0), 512)
                }
            }
        }
    }

    /// Report-only maximum-original workload. Fixture construction and the
    /// initial correctness check are outside the measured interval.
    func testMaximumOriginalHashVerification() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try PhotoPreparationLockedFiles(root: root)
        defer { files.close() }
        let file = try makeMaximumHashFixture(root: root)
        XCTAssertEqual(file.byteCount, PhotoPreparationPolicy.original)
        let expected = try files.verifiedIdentity(file)
        var lastIdentity = ""
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            do {
                // Every iteration reopens and hashes all bytes; no cached proof.
                for _ in 0..<4 {
                    lastIdentity = try autoreleasepool { try files.verifiedIdentity(file) }
                }
            } catch { XCTFail("Original hash verification failed: \(error)") }
        }
        XCTAssertEqual(lastIdentity, expected)
    }

    private func makeMaximumHashFixture(root: URL) throws -> PhotoPreparationFile {
        let asset = UUID(), token = [UUID(), UUID(), asset].map { $0.uuidString.lowercased() }.joined(separator: "/")
        let url = root.appendingPathComponent("PhotoPreparation").appendingPathComponent(token)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw PhotoPreparationFailure.unavailable }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        // Synthetic file bytes exercise only the hash owner, not image decode.
        let chunk = Data(repeating: 0x5a, count: 64 * 1024)
        var hash = SHA256()
        for _ in 0..<512 { try handle.write(contentsOf: chunk); hash.update(data: chunk) }
        try handle.synchronize()
        return .init(assetID: asset, generation: UUID(), token: token, byteCount: 32 * 1024 * 1024,
            sha256: hash.finalize().map { String(format: "%02x", $0) }.joined(), contentType: "image/jpeg")
    }

    func testAudioVideoFileAdmission() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Reuse the canonical WAV fixture; sparse image/video files exercise byte admission, not playback.
        for name in ["cover.webp", "video.mp4"] {
            let url = directory.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 1_024 * 1_024)
            try handle.close()
        }
        try makeInferenceTestPCM16WAVData(frameCount: 48_000)
            .write(to: directory.appendingPathComponent("audio.wav"))
        let payload = PendingScanPayload(
            id: "benchmark", localImagePaths: ["cover.webp"],
            localAudioPaths: ["audio.wav"], localVideoPaths: ["video.mp4"]
        )
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            do {
                for _ in 0..<100 {
                    let items = MediaStagingContract.uploadItems(
                        for: payload, userId: "synthetic", documentsDirectory: directory
                    )
                    try MediaStagingContract.validateUploadBudget(items)
                    XCTAssertEqual(items.count, 3)
                }
            } catch {
                XCTFail("File admission failed: \(error)")
            }
        }
    }

    func testInferenceResponseMapping() throws {
        let data = Data("""
        {"success":true,"data":{"scan_id":"benchmark","is_biological_subject":true,
        "is_live_capture":true,"ecology_type":"wild","is_invasive":false,
        "scientific_name":"Danaus plexippus","common_name":"Monarch Butterfly",
        "confidence_score":0.98,"insight_data":{"hazard_type":"none","ai_reasoning":"Synthetic fixture."}}}
        """.utf8)
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            do {
                for _ in 0..<100 {
                    let response = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)
                    XCTAssertTrue(IdentifySuccessEnvelopeValidator.isUsable(response))
                    let species = SpeciesData(
                        fromEdgeResponse: response.data, locationName: nil,
                        weatherCondition: nil, weatherTemperatureF: nil
                    )
                    XCTAssertEqual(species.scanId, "benchmark")
                }
            } catch {
                XCTFail("Response mapping failed: \(error)")
            }
        }
    }
}
