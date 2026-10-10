import Foundation

/// Byte-only validation for immutable history audio. This does not establish
/// ownership, a digest, upload readiness, or permission to execute inference.
enum ObservationAudioContainer {
    struct Inspection: Equatable, Sendable {
        let sampleCount: Int
        let dataOffset: Int
    }

    static func isValid(_ data: Data) -> Bool { inspect(data) != nil }

    static func inspect(_ data: Data) -> Inspection? {
        guard (46...2_700_000).contains(data.count) else { return nil }
        return data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            func tag(_ offset: Int, _ expected: String) -> Bool {
                expected.utf8.enumerated().allSatisfy { index, byte in
                    bytes[offset + index] == byte
                }
            }
            func word(_ offset: Int) -> Int {
                Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            }
            func doubleWord(_ offset: Int) -> Int {
                word(offset) | (word(offset + 2) << 16)
            }
            guard tag(0, "RIFF"), doubleWord(4) == bytes.count - 8,
                  tag(8, "WAVE"), tag(12, "fmt "), doubleWord(16) == 16,
                  word(20) == 1, word(22) == 1,
                  doubleWord(24) == 44_100, doubleWord(28) == 88_200,
                  word(32) == 2, word(34) == 16 else { return nil }

            var offset = 36
            if tag(offset, "FLLR") {
                let count = doubleWord(offset + 4)
                guard (1...4_096).contains(count) else { return nil }
                let end = offset + 8 + count + count % 2
                guard end <= bytes.count - 10,
                      bytes[(offset + 8)..<end].allSatisfy({ $0 == 0 }) else {
                    return nil
                }
                offset = end
            }
            guard offset + 10 <= bytes.count, tag(offset, "data") else { return nil }
            let count = doubleWord(offset + 4)
            guard count >= 2, count.isMultiple(of: 2), offset + 8 + count == bytes.count else { return nil }
            return Inspection(sampleCount: count / 2, dataOffset: offset + 8)
        }
    }
}
