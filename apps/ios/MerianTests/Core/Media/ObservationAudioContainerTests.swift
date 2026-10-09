import Foundation
@testable import Merian
import Testing

@Suite("Immutable history audio container")
struct ObservationAudioContainerTests {
    @Test(arguments: [0, 1, 2, 4_044, 4_096])
    func acceptsCompactAndZeroFilledCoreAudioPadding(padding: Int) {
        let data = fixture(padding: padding)
        #expect(ObservationAudioContainer.isValid(data))
        #expect(ObservationAudioContainer.inspect(data) == .init(sampleCount: 1, dataOffset: padding == 0 ? 44 : 52 + padding + padding % 2))
        // Data slices need not have a zero startIndex.
        var prefixed = Data([0xFF])
        prefixed.append(data)
        #expect(ObservationAudioContainer.isValid(prefixed.dropFirst()))
    }

    @Test(arguments: [0, 4, 8, 12, 16, 20, 22, 24, 28, 32, 34, 36, 40])
    func rejectsEveryChangedHeaderField(offset: Int) {
        var data = fixture()
        data[offset] ^= 1
        #expect(!ObservationAudioContainer.isValid(data))
    }

    @Test func rejectsTruncationTrailingBytesAndEmptyOrOddPCM() {
        let data = fixture()
        for count in 0..<data.count {
            #expect(!ObservationAudioContainer.isValid(data.prefix(count)))
        }
        for count in [0, 1, 3] {
            #expect(!ObservationAudioContainer.isValid(fixture(sampleBytes: count)))
        }
        var trailing = data
        trailing.append(contentsOf: "LISTprivate".utf8)
        setWord(UInt32(trailing.count - 8), at: 4, in: &trailing)
        #expect(!ObservationAudioContainer.isValid(trailing))
    }

    @Test func rejectsNonzeroPaddingOversizedPaddingAndOverflowLengths() {
        for offset in [44, 45] {
            var data = fixture(padding: 1)
            data[offset] = 1 // Includes the odd chunk's alignment byte.
            #expect(!ObservationAudioContainer.isValid(data))
        }
        #expect(!ObservationAudioContainer.isValid(fixture(padding: 4_097)))
        for offset in [4, 40] {
            var data = fixture(padding: 2)
            setWord(.max, at: offset, in: &data)
            #expect(!ObservationAudioContainer.isValid(data))
        }
    }

    @Test func enforcesExactByteBudgetWithoutRewriting() {
        let maximum = fixture(sampleBytes: 2_700_000 - 44)
        #expect(ObservationAudioContainer.isValid(maximum))
        #expect(!ObservationAudioContainer.isValid(fixture(sampleBytes: 2_700_002 - 44)))
        #expect(maximum.count == 2_700_000)
    }

    @Test func acceptsActualPreparedBytesWithoutChangingOriginalSamples() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.wav")
        let original = makeInferenceTestPCM16WAVData(
            sampleRate: 44_100, frameCount: 4_097,
            sampleAt: { Int16(truncatingIfNeeded: $0 * 7_919 + 12_345) }
        )
        try original.write(to: source)
        let prepared = try await InferenceAudioPreparer.prepareLocalFile(at: source, outputDirectory: directory)
        let bytes = try Data(contentsOf: prepared)
        #expect(ObservationAudioContainer.isValid(bytes))
        #expect(try inferenceTestWAVPCMData(bytes) == inferenceTestWAVPCMData(original))
        #expect(try Data(contentsOf: source) == original)
    }

    private func fixture(padding: Int = 0, sampleBytes: Int = 2) -> Data {
        var data = makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: 1, sampleAt: { _ in 123 })
        data.removeSubrange(36..<data.count)
        if padding > 0 {
            data.append(contentsOf: "FLLR".utf8)
            appendWord(UInt32(padding), to: &data)
            data.append(Data(repeating: 0, count: padding + padding % 2))
        }
        data.append(contentsOf: "data".utf8)
        appendWord(UInt32(sampleBytes), to: &data)
        data.append(Data(repeating: 0x7F, count: sampleBytes))
        setWord(UInt32(data.count - 8), at: 4, in: &data)
        return data
    }

    private func appendWord(_ value: UInt32, to data: inout Data) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private func setWord(_ value: UInt32, at offset: Int, in data: inout Data) {
        var bytes = Data()
        appendWord(value, to: &bytes)
        data.replaceSubrange(offset..<(offset + 4), with: bytes)
    }
}
