import Foundation
@testable import Merian
import Testing

@Suite("Inference audio preparation")
struct InferenceAudioPreparerTests {
    @Test func transcodesNoncanonicalWAVToDocumentsOwnedCanonicalWAV() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("historical.wav")
        try writePCM16WAV(
            to: sourceURL,
            sampleRate: 48_000,
            channels: 2,
            frameCount: 12_000
        )
        let outputDirectory = directory.appendingPathComponent("prepared")

        #expect(
            await InferenceAudioPreparer.durableStorageContentType(
                at: sourceURL
            ) == "audio/wav"
        )

        let outputURL = try await InferenceAudioPreparer.prepareLocalFile(
            at: sourceURL,
            outputDirectory: outputDirectory
        )

        #expect(outputURL.pathExtension == "wav")
        #expect(
            outputURL.deletingLastPathComponent().standardizedFileURL.path ==
                outputDirectory.standardizedFileURL.path
        )
        #expect(outputURL != sourceURL)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(InferenceAudioPreparer.isCanonicalPreparedWAV(at: outputURL))
    }

    @Test func acceptsHardwareRatePCMAsEdgeCompatibleWithoutCallingItCanonical() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("hardware.wav")
        try writePCM16WAV(
            to: sourceURL,
            sampleRate: 48_000,
            channels: 2,
            frameCount: 128
        )

        #expect(InferenceAudioPreparer.isEdgeCompatibleWAV(at: sourceURL))
        #expect(!InferenceAudioPreparer.isCanonicalPreparedWAV(at: sourceURL))
        #expect(InferenceAudioPreparer.isQueueEligibleInferenceAudioPath(
            sourceURL.path
        ))
        try MerianNetworkClient.validateInlineAudioFilesForInference(
            fileURLs: [sourceURL]
        )
    }

    @Test func rejectsExtensionSpoofingAndRemotePathStrings() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeWAV = directory.appendingPathComponent("not-a-wave.wav")
        try Data("not audio".utf8).write(to: fakeWAV)

        #expect(!InferenceAudioPreparer.isEdgeCompatibleWAV(at: fakeWAV))
        #expect(throws: MerianError.invalidResponse) {
            try MerianNetworkClient.validateInlineAudioFilesForInference(
                fileURLs: [fakeWAV]
            )
        }
        #expect(InferenceAudioPreparer.isCanonicalInferencePath("recording.wav"))
        #expect(InferenceAudioPreparer.isCanonicalInferencePath("/tmp/recording.WAV"))
        #expect(!InferenceAudioPreparer.isCanonicalInferencePath("recording.m4a"))
        #expect(!InferenceAudioPreparer.isCanonicalInferencePath(
            "https://media.merian.app/recording.wav"
        ))
        #expect(!InferenceAudioPreparer.isQueueEligibleInferenceAudioPath(
            fakeWAV.path
        ))
    }

    @Test func boundsUnknownLengthRemoteDownloadAndRemovesPartialFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let remoteURL = try #require(URL(
            string: "https://audio-download-test.invalid/\(UUID().uuidString).m4a"
        ))
        BoundedAudioURLProtocol.payloadStore.set(
            Data(
                repeating: 0x41,
                count: MerianConfig.audioPayloadMaxBytes + 1
            ),
            for: remoteURL
        )
        defer { BoundedAudioURLProtocol.payloadStore.remove(remoteURL) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundedAudioURLProtocol.self]
        await #expect(
            throws: InferenceAudioPreparationError.payloadTooLarge
        ) {
            _ = try await InferenceAudioPreparer.downloadRemoteSource(
                from: remoteURL,
                configuration: configuration,
                outputDirectory: directory
            )
        }

        let remainingFiles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(remainingFiles.isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("inference-audio-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func writePCM16WAV(
        to url: URL,
        sampleRate: UInt32,
        channels: UInt16,
        frameCount: Int
    ) throws {
        let dataByteCount = UInt32(frameCount * Int(channels) * 2)
        var data = Data()
        appendASCII("RIFF", to: &data)
        appendLittleEndian(UInt32(36) + dataByteCount, to: &data)
        appendASCII("WAVE", to: &data)
        appendASCII("fmt ", to: &data)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(channels, to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(sampleRate * UInt32(channels) * 2, to: &data)
        appendLittleEndian(channels * 2, to: &data)
        appendLittleEndian(UInt16(16), to: &data)
        appendASCII("data", to: &data)
        appendLittleEndian(dataByteCount, to: &data)
        data.append(Data(repeating: 0, count: Int(dataByteCount)))
        try data.write(to: url)
    }

    private func appendASCII(_ value: String, to data: inout Data) {
        data.append(contentsOf: value.utf8)
    }

    private func appendLittleEndian<T: FixedWidthInteger>(
        _ value: T,
        to data: inout Data
    ) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

private final class BoundedAudioPayloadStore: @unchecked Sendable {
    private let lock = NSLock()
    private var payloads: [URL: Data] = [:]

    func set(_ data: Data, for url: URL) {
        lock.withLock { payloads[url] = data }
    }

    func payload(for url: URL) -> Data? {
        lock.withLock { payloads[url] }
    }

    func remove(_ url: URL) {
        lock.withLock { payloads[url] = nil }
    }
}

private class BoundedAudioURLProtocol: URLProtocol, @unchecked Sendable {
    static let payloadStore = BoundedAudioPayloadStore()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "audio-download-test.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let payload = Self.payloadStore.payload(for: url),
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "audio/mp4"]
              ) else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.resourceUnavailable)
            )
            return
        }
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
