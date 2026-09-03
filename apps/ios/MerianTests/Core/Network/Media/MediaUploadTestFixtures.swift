import Foundation
import Testing

@testable import Merian

enum MediaUploadTestFixtures {
    static let bytes = Data([0, 1, 127, 255])
    static let signedURL = "https://storage.example/put/media?X-Amz-SignedHeaders=content-length%3Bcontent-type%3Bhost"

    static func presignedURL(
        signedURL: String = Self.signedURL,
        contentType: String = "video/mp4",
        size: Int = bytes.count,
        headers: [String: String]? = nil
    ) -> PreSignedURL {
        PreSignedURL(
            fileName: "media.mp4",
            signedUrl: signedURL,
            objectKey: "staging/synthetic-owner/media.mp4",
            requiredHeaders: headers ?? ["Content-Type": contentType, "Content-Length": String(size)],
            mediaAssetId: nil,
            mediaSessionId: nil
        )
    }

    static func signingResponse(_ urls: [PreSignedURL]) throws -> String {
        let data = try JSONEncoder().encode(PreSignedURLResponse(urls: urls))
        return try #require(String(data: data, encoding: .utf8))
    }
}

/// Each test owns a uniquely named disposable directory and its synthetic bytes.
struct NetworkMediaFileFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("merian-network-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func write(_ data: Data = MediaUploadTestFixtures.bytes, name: String = "media.mp4") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    func sizedFile(_ size: Int, name: String = "media.mp4") throws -> URL {
        let url = try write(Data(), name: name)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(size))
        return url
    }

    func close() {
        try? FileManager.default.removeItem(at: directory)
    }
}
