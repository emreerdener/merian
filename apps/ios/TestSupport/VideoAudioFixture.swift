import CryptoKit
import Foundation

/// Checked-in synthetic input, copied into a private disposable root for each test.
/// Product extraction, transcoding, retention and cancellation still run normally.
struct VideoAudioFixture: Sendable {
    let root: URL
    let videoURL: URL
    let outputDirectory: URL

    init(
        channels: Int?, amplitude: Double = 0.2,
        width: Int = 64, height: Int = 64, frameCount: Int = 30,
        transform: CGAffineTransform = .identity
    ) async throws {
        try Task.checkCancellation()
        let directory = try Self.resourceDirectory()
        let matches = try Self.catalog(in: directory).filter {
            $0.channels == channels && $0.amplitude == amplitude && $0.width == width
                && $0.height == height && $0.frameCount == frameCount
                && $0.transform == [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty]
        }
        guard matches.count == 1, let entry = matches.first else { throw FixtureError.unsupportedConfiguration }
        let bytes = try Self.validatedBytes(entry, in: directory)
        try Task.checkCancellation()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("video-audio-tests-\(UUID().uuidString)")
        videoURL = root.appendingPathComponent("capture.mp4")
        outputDirectory = root.appendingPathComponent("prepared")
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try bytes.write(to: videoURL, options: .withoutOverwriting)
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func outputFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    enum FixtureError: Error, Equatable { case missingResource, invalidCatalog, invalidMedia, unsupportedConfiguration }

    struct Entry: Codable, Sendable {
        let name: String
        let channels: Int?
        let amplitude: Double
        let width: Int
        let height: Int
        let frameCount: Int
        let transform: [Double]
        let byteCount: Int
        let sha256: String
    }

    private struct Catalog: Decodable {
        let version: Int
        let fixtures: [Entry]
    }

    static func resourceDirectory() throws -> URL {
        guard let directory = Bundle(for: VideoFixtureBundleAnchor.self).resourceURL,
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("merian-video-fixtures.json").path)
        else { throw FixtureError.missingResource }
        return directory
    }

    static func catalog(in directory: URL) throws -> [Entry] {
        let bytes = try Data(contentsOf: directory.appendingPathComponent("merian-video-fixtures.json"))
        let catalog = try JSONDecoder().decode(Catalog.self, from: bytes)
        guard catalog.version == 1, catalog.fixtures.count == 9,
              Set(catalog.fixtures.map(\.name)).count == catalog.fixtures.count,
              catalog.fixtures.allSatisfy({ entry in
                  entry.name.range(of: #"^[a-z][a-z0-9-]{0,63}$"#, options: .regularExpression) != nil
                      && (entry.channels == nil || entry.channels == 1 || entry.channels == 2)
                      && [0.01, 0.2].contains(entry.amplitude)
                      && (2...2048).contains(entry.width) && entry.width.isMultiple(of: 2)
                      && (2...2048).contains(entry.height) && entry.height.isMultiple(of: 2)
                      && (3...150).contains(entry.frameCount) && entry.transform.count == 6
                      && entry.transform.allSatisfy(\.isFinite)
                      && (1...1_048_576).contains(entry.byteCount)
                      && entry.sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil
              }) else { throw FixtureError.invalidCatalog }
        return catalog.fixtures
    }

    static func validatedBytes(_ entry: Entry, in directory: URL) throws -> Data {
        // Validate names here too: integrity tests call this boundary independently.
        guard entry.name.range(of: #"^[a-z][a-z0-9-]{0,63}$"#, options: .regularExpression) != nil,
              (1...1_048_576).contains(entry.byteCount) else { throw FixtureError.invalidCatalog }
        let url = directory.appendingPathComponent("merian-video-" + entry.name + ".mp4")
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              values.fileSize == entry.byteCount else { throw FixtureError.invalidMedia }
        let bytes = try Data(contentsOf: url)
        guard bytes.count == entry.byteCount,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == entry.sha256
        else { throw FixtureError.invalidMedia }
        return bytes
    }
}

private final class VideoFixtureBundleAnchor: NSObject {}
