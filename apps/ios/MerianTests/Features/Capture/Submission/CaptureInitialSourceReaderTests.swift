import Foundation
@testable import Merian
import Testing
import UIKit

@Suite("Initial Capture producer bytes")
struct CaptureInitialSourceReaderTests {
    @Test @MainActor func imageValidationProducesWireMIMEType() throws {
        let image = UIGraphicsImageRenderer(size: .init(width: 4, height: 4)).image { _ in
            UIColor.green.setFill(); UIRectFill(.init(x: 0, y: 0, width: 4, height: 4))
        }
        let jpeg = try #require(image.jpegData(compressionQuality: 0.8))
        #expect(try CaptureInitialSourceAttempt.imageContentType(for: jpeg) == "image/jpeg")
        let png = try #require(image.pngData())
        #expect(try CaptureInitialSourceAttempt.imageContentType(for: png) == "image/png")
    }

    @Test func readRejectsSymlinkAndOversizeWithoutRemovingProducerFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.wav"), link = root.appendingPathComponent("link.wav")
        let bytes = Data(repeating: 7, count: 64)
        try bytes.write(to: original)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        let reader = CaptureInitialSourceReader()
        #expect(try await reader.read(original, maximumBytes: 64) == bytes)
        await #expect(throws: (any Error).self) { try await reader.read(link, maximumBytes: 64) }
        await #expect(throws: (any Error).self) { try await reader.read(original, maximumBytes: 63) }
        #expect(try Data(contentsOf: original) == bytes)
    }
}
