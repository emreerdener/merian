// A Blackman-windowed sinc evaluates the low-pass-filtered signal directly at
// output times. A radius of 32 samples at the lower rate and a 90% Nyquist cutoff leave a
// transition band before the lower sample rate's Nyquist frequency.
const FILTER_RADIUS = 32;
const CUTOFF_RATIO = 0.9;
const PHASE_COUNT = 128;
// Per-call bounds: <= 8 MB of coefficients and <= 100 million filter taps.
// Callers also bound decoded and output sample counts by their media budget.
const MAX_COEFFICIENTS = 2_000_000;
const MAX_FILTER_OPERATIONS = 100_000_000;

export class WavProcessingBudgetError extends Error {
  override name = "WavProcessingBudgetError";
}

/**
 * Band-limited sample-rate conversion, with no added group delay or tail.
 * Coefficients are interpolated between fractional phases; per-phase DC gain
 * is one. Endpoint replication supplies unavailable samples at clip boundaries.
 * No signal-level normalization, spectral enhancement, or noise gate is used.
 */
export function resampleBandlimited(
  input: Float32Array,
  inputRate: number,
  outputRate: number,
  maxOutputSamples: number,
): Float32Array {
  if (
    !Number.isSafeInteger(inputRate) || inputRate <= 0 ||
    !Number.isSafeInteger(outputRate) || outputRate <= 0 ||
    !Number.isSafeInteger(maxOutputSamples) || maxOutputSamples < 0
  ) throw new Error("WAV: invalid resampling rate or budget");

  const ratio = inputRate / outputRate;
  const outputLength = Math.floor(input.length / ratio);
  if (!Number.isSafeInteger(outputLength) || outputLength > maxOutputSamples) {
    throw new WavProcessingBudgetError(
      "WAV: resampled audio exceeds processing budget",
    );
  }
  for (const sample of input) {
    if (!Number.isFinite(sample)) throw new Error("WAV: non-finite PCM sample");
  }
  if (inputRate === outputRate) return input;
  if (outputLength === 0) return new Float32Array(0);

  const scale = Math.min(1, 1 / ratio);
  const radius = Math.ceil(FILTER_RADIUS / scale);
  // Include the rightmost sample of phase 1 so adjacent phases share indexes.
  const taps = 2 * radius + 2;
  const coefficientCount = taps * (PHASE_COUNT + 1);
  if (
    coefficientCount > MAX_COEFFICIENTS ||
    outputLength * taps > MAX_FILTER_OPERATIONS
  ) {
    throw new WavProcessingBudgetError(
      "WAV: resampling work exceeds processing budget",
    );
  }

  const coefficients = new Float32Array(coefficientCount);
  for (let phase = 0; phase <= PHASE_COUNT; phase++) {
    const base = phase * taps;
    let gain = 0;
    for (let tap = 0; tap < taps; tap++) {
      const distance = tap - radius - phase / PHASE_COUNT;
      const windowPosition = distance * scale / FILTER_RADIUS;
      if (Math.abs(windowPosition) >= 1) continue;
      const argument = Math.PI * CUTOFF_RATIO * scale * distance;
      const sinc = argument === 0 ? 1 : Math.sin(argument) / argument;
      const window = 0.42 + 0.5 * Math.cos(Math.PI * windowPosition) +
        0.08 * Math.cos(2 * Math.PI * windowPosition);
      const weight = sinc * window;
      coefficients[base + tap] = weight;
      gain += weight;
    }
    for (let tap = 0; tap < taps; tap++) coefficients[base + tap] /= gain;
  }

  const output = new Float32Array(outputLength);
  for (let i = 0; i < output.length; i++) {
    const source = i * ratio;
    const center = Math.floor(source);
    const fractionalPhase = (source - center) * PHASE_COUNT;
    const phase = Math.floor(fractionalPhase);
    const fraction = fractionalPhase - phase;
    const base = phase * taps;
    let value = 0;
    for (let tap = 0; tap < taps; tap++) {
      const first = coefficients[base + tap];
      const weight = first +
        (coefficients[base + taps + tap] - first) * fraction;
      const index = Math.max(
        0,
        Math.min(input.length - 1, center + tap - radius),
      );
      value += input[index] * weight;
    }
    output[i] = value;
  }
  return output;
}
