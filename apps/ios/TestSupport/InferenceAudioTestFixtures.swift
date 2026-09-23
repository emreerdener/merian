import Foundation

func makeInferenceTestPCM16WAVData(
    sampleRate: UInt32 = 48_000,
    channels: UInt16 = 1,
    frameCount: Int = 128,
    sampleAt: ((Int) -> Int16)? = nil
) -> Data {
    let dataByteCount = UInt32(frameCount * Int(channels) * 2)
    var data = Data()

    func appendASCII(_ value: String) {
        data.append(contentsOf: value.utf8)
    }
    func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    appendASCII("RIFF")
    appendLittleEndian(UInt32(36) + dataByteCount)
    appendASCII("WAVE")
    appendASCII("fmt ")
    appendLittleEndian(UInt32(16))
    appendLittleEndian(UInt16(1))
    appendLittleEndian(channels)
    appendLittleEndian(sampleRate)
    appendLittleEndian(sampleRate * UInt32(channels) * 2)
    appendLittleEndian(channels * 2)
    appendLittleEndian(UInt16(16))
    appendASCII("data")
    appendLittleEndian(dataByteCount)
    if let sampleAt {
        for index in 0..<(frameCount * Int(channels)) {
            appendLittleEndian(sampleAt(index))
        }
    } else {
        data.append(Data(repeating: 0, count: Int(dataByteCount)))
    }
    return data
}

/// Read just the PCM chunk so harmless container padding from Core Audio does
/// not hide sample changes or make a byte-preservation assertion fail.
func inferenceTestWAVPCMData(_ wav: Data) throws -> Data {
    let bytes = [UInt8](wav)
    guard bytes.count >= 12,
          String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
          String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE" else {
        throw CocoaError(.fileReadCorruptFile)
    }
    var offset = 12
    while offset + 8 <= bytes.count {
        let size = Int(bytes[offset + 4])
            | (Int(bytes[offset + 5]) << 8)
            | (Int(bytes[offset + 6]) << 16)
            | (Int(bytes[offset + 7]) << 24)
        let start = offset + 8
        guard size <= bytes.count - start else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if String(bytes: bytes[offset..<offset + 4], encoding: .ascii) == "data" {
            return Data(bytes[start..<start + size])
        }
        offset = start + size + size % 2
    }
    throw CocoaError(.fileReadCorruptFile)
}
