import Accelerate
import AVFoundation
import Foundation

// MARK: - Spectrogram Types

struct SpectrogramColumn: Sendable {
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

// MARK: - Spectrogram Actor

/// Off-main-thread DSP worker. All FFT and mel-scale math runs here via a
/// Swift actor, keeping the Main Actor free for 60fps SwiftUI rendering.
///
/// Uses Accelerate vDSP for a 2048-point real FFT (42ms windows at 48kHz),
/// then maps linear frequency bins to 64 mel-scaled output bins spanning the
/// bioacoustically relevant range of 80Hz–16kHz (birds, insects, frogs).
actor SpectrogramActor {

    static let fftSize = 2048
    static let outputBinCount = 64

    private let log2n: vDSP_Length
    private var fftSetup: FFTSetup?
    private var hannWindow: [Float]

    // Rolling minimum RMS over ~2 seconds — used as the estimated noise floor.
    private var noiseFloorHistory: [Float] = []
    private let noiseFloorCapacity = 96

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

    /// Computes a spectrogram column from one `AVAudioPCMBuffer` tap callback.
    /// Returns `nil` if the buffer is too short or the FFT setup is unavailable.
    func process(buffer: AVAudioPCMBuffer) -> SpectrogramColumn? {
        guard let fftSetup,
              let channelData = buffer.floatChannelData?[0],
              buffer.frameLength > 0 else { return nil }

        let n = SpectrogramActor.fftSize
        let frameCount = Int(buffer.frameLength)

        // autoreleasepool prevents PCMBuffer Obj-C objects from accumulating
        // across repeated tap callbacks before ARC can collect them.
        return autoreleasepool {
            // Copy up to fftSize samples; zero-pad tail if buffer is shorter.
            var windowed = [Float](repeating: 0, count: n)
            let copyCount = min(frameCount, n)
            windowed.withUnsafeMutableBufferPointer { dst in
                guard let base = dst.baseAddress else { return }
                memcpy(base, channelData, copyCount * MemoryLayout<Float>.stride)
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
                magnitudes: melScale(mags, halfN: n / 2),
                rms: rms,
                peak: peak
            )
        }
    }

    /// Evaluates the SNR level for a processed column, updating the noise floor.
    func snrLevel(from column: SpectrogramColumn) -> SNRLevel {
        if column.peak > 0.95 { return .clipping }

        noiseFloorHistory.append(column.rms)
        if noiseFloorHistory.count > noiseFloorCapacity {
            noiseFloorHistory.removeFirst()
        }

        let floor = noiseFloorHistory.min() ?? column.rms
        guard floor > 1e-8, column.rms > 1e-8 else { return .clear }

        let snrDb = 20 * log10f(column.rms / floor)
        switch snrDb {
        case ..<10:   return .warning
        case 10..<20: return .caution
        default:      return .clear
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
    private func melScale(_ linearMags: [Float], halfN: Int) -> [Float] {
        let sampleRate: Float = 48_000
        let minHz: Float = 80
        let maxHz: Float = 16_000
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
