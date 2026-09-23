// Historical DSP, copied from add5ce9b6^ (before 23 Sep 2026).
// Retains floor-window trimming and linear interpolation intentionally.
// Only comparison/audio.ts may call these transforms, after canonical bounds.
function rmsOfWindow(
  samples: Float32Array,
  offset: number,
  length: number,
): number {
  const end = Math.min(offset + length, samples.length);
  const count = end - offset;
  if (count <= 0) return 0;
  let sum = 0;
  for (let i = offset; i < end; i++) {
    sum += samples[i] * samples[i];
  }
  return Math.sqrt(sum / count);
}

/**
 * Trims leading and trailing silence from a mono Float32 stream.
 * Uses 20 ms RMS windows with a default threshold of ~−42 dBFS.
 * `padWindows` keeps a short context buffer around the first/last active window.
 */
export function trimSilence(
  samples: Float32Array,
  sampleRate: number,
  thresholdRms = 0.008,
  windowMs = 20,
  padWindows = 2,
): Float32Array {
  const windowSize = Math.round((sampleRate * windowMs) / 1000);
  const numWindows = Math.floor(samples.length / windowSize);
  if (numWindows === 0) return samples;

  let startWindow = 0;
  for (let w = 0; w < numWindows; w++) {
    if (rmsOfWindow(samples, w * windowSize, windowSize) >= thresholdRms) {
      startWindow = Math.max(0, w - padWindows);
      break;
    }
  }

  let endWindow = numWindows - 1;
  for (let w = numWindows - 1; w >= startWindow; w--) {
    if (rmsOfWindow(samples, w * windowSize, windowSize) >= thresholdRms) {
      endWindow = Math.min(numWindows - 1, w + padWindows);
      break;
    }
  }

  const start = startWindow * windowSize;
  const end = Math.min((endWindow + 1) * windowSize, samples.length);
  return samples.slice(start, end);
}

/**
 * Linear-interpolation resampler. Used to downsample from the native hardware
 * rate (typically 48 kHz) to 16 kHz before Gemini ingestion, reducing payload size ~3×.
 */
export function resampleLinear(
  input: Float32Array,
  inputRate: number,
  outputRate: number,
): Float32Array {
  if (inputRate === outputRate) return input;
  const ratio = inputRate / outputRate;
  const outLen = Math.floor(input.length / ratio);
  if (outLen === 0) return new Float32Array(0);
  const out = new Float32Array(outLen);
  for (let i = 0; i < outLen; i++) {
    const src = i * ratio;
    const idx = Math.floor(src);
    const frac = src - idx;
    const s0 = input[idx] ?? 0;
    const s1 = input[Math.min(idx + 1, input.length - 1)] ?? 0;
    out[i] = s0 + (s1 - s0) * frac;
  }
  return out;
}
