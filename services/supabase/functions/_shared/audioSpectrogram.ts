import {
  getR2Config,
  headR2Object,
  isScanMediaR2Url,
  publicR2UrlForKey,
  putR2Object,
  type R2Config,
  r2ObjectKeyFromPublicUrl,
} from "./aws.ts";
import { fetchBoundedModerationMedia } from "./audioModeration.ts";

const FFT_SIZE = 2048;
const OUTPUT_BIN_COUNT = 128;
const PNG_SIGNATURE = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
const SPECTROGRAM_VERSION = "v1";

export interface AudioSpectrogramDependencies {
  fetchMedia?: typeof fetchBoundedModerationMedia;
  getConfig?: typeof getR2Config;
  headObject?: typeof headR2Object;
  putObject?: typeof putR2Object;
}

type DecodedWav = {
  samples: Float32Array;
  sampleRate: number;
};

export async function createAudioSpectrogramThumbnail(
  audioUrl: string,
  dependencies: AudioSpectrogramDependencies = {},
): Promise<string | null> {
  if (!isScanMediaR2Url(audioUrl)) return null;

  const fetchMedia = dependencies.fetchMedia ?? fetchBoundedModerationMedia;
  const { bytes, mimeType } = await fetchMedia(audioUrl);
  if (mimeType !== "audio/wav") return null;

  const png = await renderAudioSpectrogramPng(bytes);
  if (!png) return null;

  const sourceKey = r2ObjectKeyFromPublicUrl(audioUrl);
  if (!sourceKey) return null;
  const slashIndex = sourceKey.lastIndexOf("/");
  if (slashIndex <= 0) return null;

  const checksum = await sha256Hex(bytes);
  const thumbnailKey = `${
    sourceKey.slice(0, slashIndex)
  }/spectrogram-${SPECTROGRAM_VERSION}-${checksum}.png`;
  const thumbnailUrl = publicR2UrlForKey(thumbnailKey);
  const config = (dependencies.getConfig ?? getR2Config)();
  const headObject = dependencies.headObject ?? headR2Object;
  const existing = await headObject(thumbnailKey, config);
  if (existing.ok) return thumbnailUrl;
  if (existing.status !== 404) {
    throw new Error(
      `Audio spectrogram lookup failed with status ${existing.status}.`,
    );
  }

  const upload = await (dependencies.putObject ?? putR2Object)(
    thumbnailKey,
    png,
    "image/png",
    config,
  );
  if (!upload.ok) {
    throw new Error(
      `Audio spectrogram upload failed with status ${upload.status}.`,
    );
  }
  return thumbnailUrl;
}

export async function renderAudioSpectrogramPng(
  wavBytes: ArrayBuffer,
): Promise<Uint8Array | null> {
  const decoded = decodeWav(wavBytes);
  if (!decoded || decoded.samples.length === 0) return null;

  const columns: Float32Array[] = [];
  for (let offset = 0; offset < decoded.samples.length; offset += FFT_SIZE) {
    columns.push(
      spectrogramColumn(decoded.samples, offset, decoded.sampleRate),
    );
  }
  if (columns.length === 0) return null;

  const rgba = new Uint8Array(columns.length * OUTPUT_BIN_COUNT * 4);
  for (let columnIndex = 0; columnIndex < columns.length; columnIndex += 1) {
    const column = columns[columnIndex];
    for (let binIndex = 0; binIndex < OUTPUT_BIN_COUNT; binIndex += 1) {
      const y = OUTPUT_BIN_COUNT - binIndex - 1;
      const offset = (y * columns.length + columnIndex) * 4;
      const [red, green, blue] = palette(column[binIndex]);
      rgba[offset] = red;
      rgba[offset + 1] = green;
      rgba[offset + 2] = blue;
      rgba[offset + 3] = 255;
    }
  }

  return await encodePng(columns.length, OUTPUT_BIN_COUNT, rgba);
}

function decodeWav(buffer: ArrayBuffer): DecodedWav | null {
  if (buffer.byteLength < 44) return null;
  const view = new DataView(buffer);
  if (ascii(view, 0, 4) !== "RIFF" || ascii(view, 8, 4) !== "WAVE") {
    return null;
  }

  let format = 0;
  let channels = 0;
  let sampleRate = 0;
  let blockAlign = 0;
  let bitsPerSample = 0;
  let dataOffset = -1;
  let dataLength = 0;

  for (let offset = 12; offset + 8 <= view.byteLength;) {
    const chunkId = ascii(view, offset, 4);
    const chunkLength = view.getUint32(offset + 4, true);
    const payloadOffset = offset + 8;
    if (payloadOffset + chunkLength > view.byteLength) return null;

    if (chunkId === "fmt " && chunkLength >= 16) {
      format = view.getUint16(payloadOffset, true);
      channels = view.getUint16(payloadOffset + 2, true);
      sampleRate = view.getUint32(payloadOffset + 4, true);
      blockAlign = view.getUint16(payloadOffset + 12, true);
      bitsPerSample = view.getUint16(payloadOffset + 14, true);
      if (format === 0xfffe && chunkLength >= 40) {
        format = view.getUint16(payloadOffset + 24, true);
      }
    } else if (chunkId === "data") {
      dataOffset = payloadOffset;
      dataLength = chunkLength;
    }
    offset = payloadOffset + chunkLength + (chunkLength % 2);
  }

  if (
    (format !== 1 && format !== 3) || channels < 1 || sampleRate < 1 ||
    blockAlign < 1 || bitsPerSample < 8 || dataOffset < 0 || dataLength < 1
  ) {
    return null;
  }
  const supportedBits = format === 1
    ? [8, 16, 24, 32].includes(bitsPerSample)
    : [32, 64].includes(bitsPerSample);
  const bytesPerSample = Math.ceil(bitsPerSample / 8);
  if (!supportedBits || blockAlign < bytesPerSample * channels) return null;

  const frameCount = Math.floor(dataLength / blockAlign);
  if (frameCount < 1) return null;
  const samples = new Float32Array(frameCount);
  for (let frame = 0; frame < frameCount; frame += 1) {
    const sampleOffset = dataOffset + frame * blockAlign;
    samples[frame] = readSample(
      view,
      sampleOffset,
      format,
      bitsPerSample,
    );
  }
  return { samples, sampleRate };
}

function readSample(
  view: DataView,
  offset: number,
  format: number,
  bitsPerSample: number,
): number {
  if (format === 3) {
    if (bitsPerSample === 32) return view.getFloat32(offset, true);
    if (bitsPerSample === 64) return view.getFloat64(offset, true);
    return 0;
  }
  if (bitsPerSample === 8) return (view.getUint8(offset) - 128) / 128;
  if (bitsPerSample === 16) return view.getInt16(offset, true) / 32768;
  if (bitsPerSample === 24) {
    let value = view.getUint8(offset) |
      (view.getUint8(offset + 1) << 8) |
      (view.getUint8(offset + 2) << 16);
    if ((value & 0x800000) !== 0) value |= 0xff000000;
    return value / 8388608;
  }
  if (bitsPerSample === 32) return view.getInt32(offset, true) / 2147483648;
  return 0;
}

function spectrogramColumn(
  samples: Float32Array,
  sourceOffset: number,
  sampleRate: number,
): Float32Array {
  const real = new Float64Array(FFT_SIZE);
  const imaginary = new Float64Array(FFT_SIZE);
  for (let index = 0; index < FFT_SIZE; index += 1) {
    const sample = samples[sourceOffset + index] ?? 0;
    const window = 0.5 * (1 - Math.cos((2 * Math.PI * index) / FFT_SIZE));
    real[index] = sample * window;
  }
  fft(real, imaginary);

  const halfN = FFT_SIZE / 2;
  const linearMagnitudes = new Float32Array(halfN);
  for (let index = 0; index < halfN; index += 1) {
    const power = (real[index] ** 2 + imaginary[index] ** 2) / FFT_SIZE;
    const decibels = 10 * Math.log10(Math.max(power, 1e-12));
    linearMagnitudes[index] = clamp((decibels + 80) / 80, 0, 1);
  }
  return melScale(linearMagnitudes, sampleRate);
}

function fft(real: Float64Array, imaginary: Float64Array) {
  const count = real.length;
  for (let i = 1, j = 0; i < count; i += 1) {
    let bit = count >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) {
      [real[i], real[j]] = [real[j], real[i]];
      [imaginary[i], imaginary[j]] = [imaginary[j], imaginary[i]];
    }
  }

  for (let length = 2; length <= count; length <<= 1) {
    const angle = -2 * Math.PI / length;
    const stepReal = Math.cos(angle);
    const stepImaginary = Math.sin(angle);
    for (let start = 0; start < count; start += length) {
      let phaseReal = 1;
      let phaseImaginary = 0;
      for (let offset = 0; offset < length / 2; offset += 1) {
        const even = start + offset;
        const odd = even + length / 2;
        const oddReal = real[odd] * phaseReal - imaginary[odd] * phaseImaginary;
        const oddImaginary = real[odd] * phaseImaginary +
          imaginary[odd] * phaseReal;
        real[odd] = real[even] - oddReal;
        imaginary[odd] = imaginary[even] - oddImaginary;
        real[even] += oddReal;
        imaginary[even] += oddImaginary;
        const nextPhaseReal = phaseReal * stepReal -
          phaseImaginary * stepImaginary;
        phaseImaginary = phaseReal * stepImaginary + phaseImaginary * stepReal;
        phaseReal = nextPhaseReal;
      }
    }
  }
}

function melScale(
  linearMagnitudes: Float32Array,
  sampleRate: number,
): Float32Array {
  const halfN = linearMagnitudes.length;
  const minHz = 80;
  const maxHz = Math.min(sampleRate / 2, 16_000);
  const hzToMel = (hz: number) => 2595 * Math.log10(1 + hz / 700);
  const melToHz = (mel: number) => 700 * (10 ** (mel / 2595) - 1);
  const minMel = hzToMel(minHz);
  const maxMel = hzToMel(maxHz);
  const hzPerBin = (sampleRate / 2) / halfN;
  const binPoints = Array.from({ length: OUTPUT_BIN_COUNT + 2 }, (_, index) => {
    const mel = minMel + index * (maxMel - minMel) / (OUTPUT_BIN_COUNT + 1);
    return Math.max(
      0,
      Math.min(halfN - 1, Math.floor(melToHz(mel) / hzPerBin)),
    );
  });

  const output = new Float32Array(OUTPUT_BIN_COUNT);
  for (let outputIndex = 0; outputIndex < OUTPUT_BIN_COUNT; outputIndex += 1) {
    const low = binPoints[outputIndex];
    const center = binPoints[outputIndex + 1];
    const high = binPoints[outputIndex + 2];
    let sum = 0;
    let totalWeight = 0;
    for (let bin = low; bin <= Math.max(low, center); bin += 1) {
      const weight = (bin - low) / Math.max(center - low, 1);
      sum += linearMagnitudes[bin] * weight;
      totalWeight += weight;
    }
    for (let bin = Math.min(center + 1, high); bin <= high; bin += 1) {
      const weight = (high - bin) / Math.max(high - center, 1);
      sum += linearMagnitudes[bin] * weight;
      totalWeight += weight;
    }
    output[outputIndex] = totalWeight > 0 ? sum / totalWeight : 0;
  }
  return output;
}

function palette(value: number): [number, number, number] {
  const normalized = Math.pow(clamp(value, 0, 1), 0.85);
  const stops: Array<[number, [number, number, number]]> = [
    [0, [0.02, 0.027, 0.051]],
    [0.18, [0.02, 0.075, 0.27]],
    [0.38, [0.045, 0.30, 0.66]],
    [0.58, [0.02, 0.70, 0.78]],
    [0.78, [0.48, 0.88, 0.43]],
    [0.93, [0.98, 0.82, 0.24]],
    [1, [1, 0.98, 0.82]],
  ];
  const upperIndex = Math.max(
    0,
    stops.findIndex(([stop]) => normalized <= stop),
  );
  if (upperIndex <= 0) {
    return stops[0][1].map(toByte) as [number, number, number];
  }
  const [lowerStop, lowerColor] = stops[upperIndex - 1];
  const [upperStop, upperColor] = stops[upperIndex];
  const interpolation = (normalized - lowerStop) /
    Math.max(upperStop - lowerStop, Number.EPSILON);
  return lowerColor.map((component, index) =>
    toByte(component + (upperColor[index] - component) * interpolation)
  ) as [number, number, number];
}

async function encodePng(
  width: number,
  height: number,
  rgba: Uint8Array,
): Promise<Uint8Array> {
  const scanlines = new Uint8Array(height * (width * 4 + 1));
  for (let row = 0; row < height; row += 1) {
    const targetOffset = row * (width * 4 + 1);
    scanlines[targetOffset] = 0;
    scanlines.set(
      rgba.subarray(row * width * 4, (row + 1) * width * 4),
      targetOffset + 1,
    );
  }
  const compressedStream = new Blob([scanlines]).stream().pipeThrough(
    new CompressionStream("deflate"),
  );
  const compressed = new Uint8Array(
    await new Response(compressedStream).arrayBuffer(),
  );
  const header = new Uint8Array(13);
  const headerView = new DataView(header.buffer);
  headerView.setUint32(0, width);
  headerView.setUint32(4, height);
  header[8] = 8;
  header[9] = 6;

  return concatenate([
    PNG_SIGNATURE,
    pngChunk("IHDR", header),
    pngChunk("IDAT", compressed),
    pngChunk("IEND", new Uint8Array()),
  ]);
}

function pngChunk(type: string, data: Uint8Array): Uint8Array {
  const typeBytes = new TextEncoder().encode(type);
  const result = new Uint8Array(12 + data.length);
  const view = new DataView(result.buffer);
  view.setUint32(0, data.length);
  result.set(typeBytes, 4);
  result.set(data, 8);
  view.setUint32(8 + data.length, crc32(concatenate([typeBytes, data])));
  return result;
}

function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

async function sha256Hex(buffer: ArrayBuffer): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", buffer));
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

function ascii(view: DataView, offset: number, length: number): string {
  return String.fromCharCode(
    ...Array.from({ length }, (_, index) => view.getUint8(offset + index)),
  );
}

function concatenate(chunks: Uint8Array[]): Uint8Array {
  const output = new Uint8Array(
    chunks.reduce((sum, chunk) => sum + chunk.length, 0),
  );
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.length;
  }
  return output;
}

function toByte(value: number): number {
  return Math.max(0, Math.min(255, Math.round(value * 255)));
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.max(minimum, Math.min(maximum, value));
}

export type { R2Config };
