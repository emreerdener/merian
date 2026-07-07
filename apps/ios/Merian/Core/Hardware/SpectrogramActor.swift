import Accelerate
import AVFoundation
import Foundation

// MARK: - Spectrogram Types

struct SpectrogramColumn: Sendable, Equatable {
    let magnitudes: [Float]  // outputBinCount mel-scaled bins, 0.0–1.0 normalized
    let rms: Float           // pre-window RMS for SNR calculation
    let peak: Float          // pre-window peak for clipping detection
}

enum SNRLevel: Sendable, Equatable {
    case clear       // SNR > 20 dB — clean signal
    case caution     // 10–20 dB — some background noise
    case warning     // < 10 dB — shield microphone
    case clipping    // peak > 0.95 — move mic away
}

struct CircularBuffer<Element> {
    private var storage: [Element?]
    private var head = 0
    private var countValue = 0

    init(capacity: Int) {
        precondition(capacity > 0, "CircularBuffer capacity must be positive")
        storage = Array(repeating: nil, count: capacity)
    }

    var count: Int { countValue }

    var elements: [Element] {
        guard countValue > 0 else { return [] }
        return (0..<countValue).compactMap { storage[(head + $0) % storage.count] }
    }

    mutating func append(_ element: Element) {
        if countValue < storage.count {
            storage[(head + countValue) % storage.count] = element
            countValue += 1
            return
        }

        storage[head] = element
        head = (head + 1) % storage.count
    }

    mutating func removeAll() {
        storage = Array(repeating: nil, count: storage.count)
        head = 0
        countValue = 0
    }
}

// MARK: - Spectrogram Actor

/// Off-main-thread DSP worker. All FFT and mel-scale math runs here via a
/// Swift actor, keeping the Main Actor free for 60fps SwiftUI rendering.
///
/// Uses Accelerate vDSP for a 2048-point real FFT (42ms windows at 48kHz),
/// then maps linear frequency bins to 128 mel-scaled output bins spanning the
/// bioacoustically relevant range of 80Hz–16kHz (birds, insects, frogs).
actor SpectrogramActor {

    static let fftSize = 2048
    static let outputBinCount = 128
    private static let noiseFloorCapacity = 48

    private let log2n: vDSP_Length
    private var fftSetup: FFTSetup?
    private var hannWindow: [Float]

    // Rolling minimum RMS over ~2 seconds of 2048-frame windows — used as the estimated noise floor.
    private var noiseFloorHistory = CircularBuffer<Float>(capacity: SpectrogramActor.noiseFloorCapacity)

    init() {
        log2n = vDSP_Length(log2f(Float(SpectrogramActor.fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        hannWindow = [Float](repeating: 0, count: SpectrogramActor.fftSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(SpectrogramActor.fftSize), Int32(vDSP_HANN_DENORM))
    }

    deinit {
        if let setup = fftSetup { vDSP_destroy_fftsetup(setup) }
    }

    // MARK: - Public API

    /// Computes the first spectrogram column from an audio buffer.
    /// Returns `nil` if the buffer is too short or the FFT setup is unavailable.
    func process(buffer: AVAudioPCMBuffer) -> SpectrogramColumn? {
        processColumns(buffer: buffer).first
    }

    /// Computes one spectrogram column per 2048-frame FFT window in the buffer.
    /// Short final windows are zero-padded so the decoder does not discard audio tail data.
    func processColumns(buffer: AVAudioPCMBuffer) -> [SpectrogramColumn] {
        guard let fftSetup,
              let channelData = buffer.floatChannelData?[0],
              buffer.frameLength > 0 else { return [] }

        let n = SpectrogramActor.fftSize
        let frameCount = Int(buffer.frameLength)
        let sampleRate = Float(buffer.format.sampleRate > 0 ? buffer.format.sampleRate : 48_000)

        return stride(from: 0, to: frameCount, by: n).compactMap { offset in
            processWindow(
                channelData: channelData,
                offset: offset,
                availableFrames: frameCount - offset,
                sampleRate: sampleRate,
                fftSetup: fftSetup
            )
        }
    }

    private func processWindow(
        channelData: UnsafePointer<Float>,
        offset: Int,
        availableFrames: Int,
        sampleRate: Float,
        fftSetup: FFTSetup
    ) -> SpectrogramColumn? {
        let n = SpectrogramActor.fftSize

        // autoreleasepool prevents PCMBuffer Obj-C objects from accumulating
        // across repeated tap callbacks before ARC can collect them.
        return autoreleasepool {
            // Copy up to fftSize samples; zero-pad tail if buffer is shorter.
            var windowed = [Float](repeating: 0, count: n)
            let copyCount = min(max(availableFrames, 0), n)
            guard copyCount > 0 else { return nil }
            windowed.withUnsafeMutableBufferPointer { dst in
                guard let base = dst.baseAddress else { return }
                memcpy(base, channelData.advanced(by: offset), copyCount * MemoryLayout<Float>.stride)
            }

            // Capture RMS and peak from the raw (pre-window) signal.
            var rms: Float = 0
            vDSP_rmsqv(windowed, 1, &rms, vDSP_Length(n))
            var peak: Float = 0
            vDSP_maxmgv(windowed, 1, &peak, vDSP_Length(n))

            // Apply Hann window to suppress spectral leakage.
            vDSP_vmul(windowed, 1, hannWindow, 1, &windowed, 1, vDSP_Length(n))

            // Real FFT via split-complex packing.
            var realp = [Float](repeating: 0, count: n / 2)
            var imagp = [Float](repeating: 0, count: n / 2)
            var mags  = [Float](repeating: 0, count: n / 2)

            realp.withUnsafeMutableBufferPointer { rBuf in
                imagp.withUnsafeMutableBufferPointer { iBuf in
                    guard let rBase = rBuf.baseAddress, let iBase = iBuf.baseAddress else { return }
                    var split = DSPSplitComplex(realp: rBase, imagp: iBase)

                    windowed.withUnsafeBytes { rawBytes in
                        guard let src = rawBytes.bindMemory(to: DSPComplex.self).baseAddress else { return }
                        vDSP_ctoz(src, 2, &split, 1, vDSP_Length(n / 2))
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n / 2))
                }
            }

            // Normalise power, convert to dB, clamp to -80…0 dB, rescale to 0…1.
            var normScale: Float = 1.0 / Float(n)
            vDSP_vsmul(mags, 1, &normScale, &mags, 1, vDSP_Length(n / 2))
            var one: Float = 1
            vDSP_vdbcon(mags, 1, &one, &mags, 1, vDSP_Length(n / 2), 0)
            let minDb: Float = -80, maxDb: Float = 0
            mags = mags.map { Swift.max(0, Swift.min(1, ($0 - minDb) / (maxDb - minDb))) }

            return SpectrogramColumn(
                magnitudes: melScale(mags, halfN: n / 2, sampleRate: sampleRate),
                rms: rms,
                peak: peak
            )
        }
    }

    /// Evaluates the ambient noise level, identifying problematic environments without penalizing speech pauses.
    func snrLevel(from column: SpectrogramColumn) -> SNRLevel {
        if column.peak > 0.95 { return .clipping }

        noiseFloorHistory.append(column.rms)

        // The "floor" is the minimum RMS over the trailing window — effectively
        // stripping out transient speech/birds to find the raw room/environment noise.
        let floor = noiseFloorHistory.elements.min() ?? column.rms

        // Absolute noise floor thresholds
        // 0.08  (~ -22 dBFS) -> Heavy wind, traffic, severe interference
        // 0.015 (~ -36 dBFS) -> Noticeable hum, fans, distant highway
        if floor > 0.08 {
            return .warning
        } else if floor > 0.015 {
            return .caution
        } else {
            // Room is quiet enough (< -36 dBFS)
            return .clear
        }
    }

    func reset() {
        noiseFloorHistory.removeAll()
    }

    // MARK: - Mel Scale

    /// Maps `halfN` linear FFT magnitude bins to `outputBinCount` mel-scaled bins.
    ///
    /// Covers 80Hz–16kHz with triangular filter banks spaced on the mel scale —
    /// perceptually uniform and captures the critical 1–8kHz bird/insect ID range.
    private func melScale(_ linearMags: [Float], halfN: Int, sampleRate: Float) -> [Float] {
        let minHz: Float = 80
        let maxHz = min(sampleRate / 2, 16_000)
        let outBins = SpectrogramActor.outputBinCount

        func hzToMel(_ hz: Float) -> Float { 2595 * log10f(1 + hz / 700) }
        func melToHz(_ mel: Float) -> Float { 700 * (powf(10, mel / 2595) - 1) }

        let minMel = hzToMel(minHz)
        let maxMel = hzToMel(maxHz)
        let melPoints = (0..<(outBins + 2)).map { i in
            minMel + Float(i) * (maxMel - minMel) / Float(outBins + 1)
        }
        let hzPerBin = (sampleRate / 2) / Float(halfN)
        let binPoints = melPoints.map { Swift.max(0, Swift.min(halfN - 1, Int(melToHz($0) / hzPerBin))) }

        var output = [Float](repeating: 0, count: outBins)
        for m in 0..<outBins {
            let lo     = binPoints[m]
            let center = binPoints[m + 1]
            let hi     = binPoints[m + 2]

            var acc: Float = 0
            var totalWeight: Float = 0

            let riseEnd = Swift.max(lo, center)
            for k in lo...riseEnd {
                let w = Float(k - lo) / Float(Swift.max(center - lo, 1))
                acc += linearMags[k] * w
                totalWeight += w
            }
            let fallStart = Swift.min(center + 1, hi)
            if fallStart <= hi {
                for k in fallStart...hi {
                    let w = Float(hi - k) / Float(Swift.max(hi - center, 1))
                    acc += linearMags[k] * w
                    totalWeight += w
                }
            }
            output[m] = totalWeight > 0 ? acc / totalWeight : 0
        }
        return output
    }
}

private final class SpectrogramDecodeEOFBox: @unchecked Sendable {
    var reached = false
}

enum AudioSpectrogramDecoder {
    static func decodeColumns(fromFilePath filePath: String) async -> [SpectrogramColumn] {
        let url = URL(fileURLWithPath: filePath)

        do {
            let file = try AVAudioFile(forReading: url)
            guard let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1),
                  let converter = AVAudioConverter(from: file.processingFormat, to: outputFormat),
                  let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 2048) else {
                return []
            }

            let spectrogramActor = SpectrogramActor()
            await spectrogramActor.reset()

            var columns: [SpectrogramColumn] = []
            let eof = SpectrogramDecodeEOFBox()

            while !eof.reached {
                var error: NSError?
                let status = converter.convert(to: outputBuffer, error: &error) { requestedPackets, outStatus in
                    guard !eof.reached else {
                        outStatus.pointee = .endOfStream
                        return nil
                    }

                    guard let inputBuffer = AVAudioPCMBuffer(
                        pcmFormat: file.processingFormat,
                        frameCapacity: requestedPackets
                    ) else {
                        outStatus.pointee = .noDataNow
                        return nil
                    }

                    do {
                        try file.read(into: inputBuffer, frameCount: requestedPackets)
                        if inputBuffer.frameLength == 0 {
                            eof.reached = true
                            outStatus.pointee = .endOfStream
                            return nil
                        }
                        outStatus.pointee = .haveData
                        return inputBuffer
                    } catch {
                        eof.reached = true
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                }

                if status == .haveData, outputBuffer.frameLength > 0 {
                    let decodedColumns = await spectrogramActor.processColumns(buffer: outputBuffer)
                    columns.append(contentsOf: decodedColumns)
                    continue
                }

                if error != nil {
                    return []
                }

                if status == .inputRanDry, !eof.reached {
                    continue
                }

                break
            }

            return columns
        } catch {
            return []
        }
    }
}
