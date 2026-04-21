import { encodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";

/**
 * DUAL-MAINTENANCE: The WAV processing algorithm exists in both /audio-spec/index.ts and
 * /identify-multimodal/audio.ts. Any future changes (e.g. sample rate, thresholds) must
 * be applied to both.
 */

const TARGET_SAMPLE_RATE = 16_000;

const WAVE_FORMAT_PCM = 1;
const WAVE_FORMAT_IEEE_FLOAT = 3;

interface WavHeader {
  audioFormat: number;
  numChannels: number;
  sampleRate: number;
  bitsPerSample: number;
  dataOffset: number;
  dataLength: number;
}

export function parseWavHeader(buffer: ArrayBuffer): WavHeader {
  if (buffer.byteLength < 44) throw new Error("WAV: file too small");

  const view = new DataView(buffer);
  const bytes = new Uint8Array(buffer);
  const tag = (o: number) =>
    String.fromCharCode(bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3]);

  if (tag(0) !== "RIFF") throw new Error("WAV: missing RIFF signature");
  if (tag(8) !== "WAVE") throw new Error("WAV: missing WAVE identifier");

  let audioFormat = 0;
  let numChannels = 0;
  let sampleRate = 0;
  let bitsPerSample = 0;
  let dataOffset = -1;
  let dataLength = 0;
  let offset = 12;

  while (offset + 8 <= buffer.byteLength) {
    const chunkTag = tag(offset);
    const chunkSize = view.getUint32(offset + 4, true);

    if (chunkTag === "fmt ") {
      audioFormat = view.getUint16(offset + 8, true);
      numChannels = view.getUint16(offset + 10, true);
      sampleRate = view.getUint32(offset + 12, true);
      bitsPerSample = view.getUint16(offset + 22, true);
    } else if (chunkTag === "data") {
      dataOffset = offset + 8;
      dataLength = chunkSize;
      break;
    }

    offset += 8 + chunkSize;
    if (chunkSize % 2 !== 0) offset++; // WAV chunk padding byte
  }

  if (sampleRate === 0) throw new Error("WAV: fmt chunk not found");
  if (dataOffset === -1) throw new Error("WAV: data chunk not found");

  return { audioFormat, numChannels, sampleRate, bitsPerSample, dataOffset, dataLength };
}

export function extractSamplesAsFloat32(buffer: ArrayBuffer, header: WavHeader): Float32Array {
  const { audioFormat, bitsPerSample, dataOffset, dataLength } = header;
  const view = new DataView(buffer, dataOffset, dataLength);

  if (audioFormat === WAVE_FORMAT_PCM && bitsPerSample === 16) {
    const count = dataLength / 2;
    const out = new Float32Array(count);
    for (let i = 0; i < count; i++) {
      out[i] = view.getInt16(i * 2, true) / 32768.0;
    }
    return out;
  }

  if (audioFormat === WAVE_FORMAT_IEEE_FLOAT && bitsPerSample === 32) {
    const count = dataLength / 4;
    const out = new Float32Array(count);
    for (let i = 0; i < count; i++) {
      out[i] = view.getFloat32(i * 4, true);
    }
    return out;
  }

  throw new Error(
    `WAV: unsupported format (audioFormat=${audioFormat}, bitsPerSample=${bitsPerSample})`,
  );
}

export function mixToMono(samples: Float32Array, numChannels: number): Float32Array {
  if (numChannels === 1) return samples;
  const monoLen = Math.floor(samples.length / numChannels);
  const mono = new Float32Array(monoLen);
  for (let i = 0; i < monoLen; i++) {
    let sum = 0;
    for (let ch = 0; ch < numChannels; ch++) {
      sum += samples[i * numChannels + ch];
    }
    mono[i] = sum / numChannels;
  }
  return mono;
}

function rmsOfWindow(samples: Float32Array, offset: number, length: number): number {
  const end = Math.min(offset + length, samples.length);
  const count = end - offset;
  if (count <= 0) return 0;
  let sum = 0;
  for (let i = offset; i < end; i++) {
    sum += samples[i] * samples[i];
  }
  return Math.sqrt(sum / count);
}

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

export function encodeWav16(samples: Float32Array, sampleRate: number): Uint8Array {
  const dataSize = samples.length * 2;
  const buf = new ArrayBuffer(44 + dataSize);
  const view = new DataView(buf);
  const bytes = new Uint8Array(buf);

  const w4 = (o: number, s: string) => {
    for (let i = 0; i < 4; i++) view.setUint8(o + i, s.charCodeAt(i));
  };

  w4(0, "RIFF");
  view.setUint32(4, 36 + dataSize, true);
  w4(8, "WAVE");
  w4(12, "fmt ");
  view.setUint32(16, 16, true);          // fmt chunk size
  view.setUint16(20, 1, true);           // PCM
  view.setUint16(22, 1, true);           // mono
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true); // byteRate
  view.setUint16(32, 2, true);           // blockAlign
  view.setUint16(34, 16, true);          // bitsPerSample
  w4(36, "data");
  view.setUint32(40, dataSize, true);

  for (let i = 0; i < samples.length; i++) {
    const clamped = Math.max(-1, Math.min(1, samples[i]));
    view.setInt16(44 + i * 2, Math.round(clamped * 32767), true);
  }

  return bytes;
}

export function processWAV(rawWavBuffer: ArrayBuffer): string {
  const header = parseWavHeader(rawWavBuffer);
  const interleaved = extractSamplesAsFloat32(rawWavBuffer, header);
  const mono = mixToMono(interleaved, header.numChannels);
  const trimmed = trimSilence(mono, header.sampleRate);
  const resampled = resampleLinear(trimmed, header.sampleRate, TARGET_SAMPLE_RATE);
  if (resampled.length < 8_000) {
    throw new Error("Audio too short to identify. Please record a longer clip.");
  }
  const processedWav = encodeWav16(resampled, TARGET_SAMPLE_RATE);
  return encodeBase64(processedWav);
}
