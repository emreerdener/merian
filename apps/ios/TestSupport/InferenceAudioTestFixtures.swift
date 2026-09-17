import Foundation

func makeInferenceTestPCM16WAVData(
    sampleRate: UInt32 = 48_000,
    channels: UInt16 = 1,
    frameCount: Int = 128
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
    data.append(Data(repeating: 0, count: Int(dataByteCount)))
    return data
}
