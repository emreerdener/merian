import { processWavBuffer } from "../../../../services/supabase/functions/_shared/audioProcessing.ts";
import { processMultimodalWAV } from "../../../../services/supabase/functions/identify-multimodal/audio.ts";
import { decodeBase64 } from "../../../../services/supabase/functions/_shared/encoding.ts";
import {
  encodeWav16,
  extractSamplesAsFloat32,
  parseWavHeader,
  trimSilence,
} from "../../../../services/supabase/functions/audio-spec/wav.ts";

const [source, previous, destination] = Deno.args;
if (!source || !previous || !destination || Deno.args.length !== 3) {
  throw new Error(
    "Expected source packet, previous verification packet, and NEW output directory",
  );
}
// Refuse to overwrite a frozen or previously measured packet.
await Deno.mkdir(destination, { mode: 0o700 });
const hash = async (bytes: Uint8Array) =>
  Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(bytes).buffer),
    ),
  ).map((b) => b.toString(16).padStart(2, "0")).join("");
const freezeBytes = await Deno.readFile(`${source}/freeze.json`);
const expectedFreeze =
  "415a055676d36ae0bf93aa8856a2b86d67188c97ea51f5c42e20400909489c8c";
if (await hash(freezeBytes) !== expectedFreeze) {
  throw new Error("Source freeze changed");
}
const freeze = JSON.parse(new TextDecoder().decode(freezeBytes));
for (const file of freeze.files) {
  const bytes = await Deno.readFile(`${source}/${file.path}`);
  if (
    bytes.byteLength !== file.byteLength || await hash(bytes) !== file.sha256
  ) throw new Error(`Source changed: ${file.path}`);
}
const previousFreezeBytes = await Deno.readFile(`${previous}/freeze.json`);
const expectedPreviousFreeze =
  "95c4c3e05b80b90f91bcaeba42b148c27107823f5c8f025a61079b6d1abaad94";
if (await hash(previousFreezeBytes) !== expectedPreviousFreeze) {
  throw new Error("Previous verification freeze changed");
}
const previousFreeze = JSON.parse(
  new TextDecoder().decode(previousFreezeBytes),
);
for (const file of previousFreeze.files) {
  const bytes = await Deno.readFile(`${previous}/${file.path}`);
  if (
    bytes.byteLength !== file.byteLength || await hash(bytes) !== file.sha256
  ) throw new Error(`Previous verification changed: ${file.path}`);
}
const baseline = JSON.parse(
  await Deno.readTextFile(`${previous}/analysis.json`),
);
const elapsed = (work: () => void) => {
  const start = performance.now();
  work();
  return performance.now() - start;
};
const timing = (work: () => void) => {
  work();
  const milliseconds = Array.from({ length: 5 }, () => elapsed(work));
  const sorted = [...milliseconds].sort((a, b) => a - b);
  return {
    repetitions: milliseconds.length,
    milliseconds,
    medianMilliseconds: sorted[2],
    maxMilliseconds: sorted[4],
  };
};
const metrics = (samples: Float32Array) => {
  let peak = 0, sum = 0, nonzero = 0;
  for (const sample of samples) {
    peak = Math.max(peak, Math.abs(sample));
    sum += sample * sample;
    if (sample !== 0) nonzero++;
  }
  return {
    sampleCount: samples.length,
    peak,
    rms: Math.sqrt(sum / samples.length),
    nonzeroSampleCount: nonzero,
  };
};
const cases = [];
for (let number = 13; number <= 18; number++) {
  const caseId = `c${number.toString().padStart(4, "0")}`;
  const file = `assets/a${number.toString().padStart(4, "0")}0.wav`;
  const bytes = await Deno.readFile(`${source}/${file}`);
  const buffer = bytes.buffer as ArrayBuffer;
  const header = parseWavHeader(buffer);
  if (
    header.numChannels !== 1 || header.sampleRate !== 44100 ||
    header.bitsPerSample !== 16
  ) throw new Error("Unexpected frozen input format");
  const inputSamples = extractSamplesAsFloat32(buffer, header);
  const firstLocalCallMilliseconds = elapsed(() => processWavBuffer(buffer));
  const runtime = timing(() => processWavBuffer(buffer));
  const result = processWavBuffer(buffer);
  const routeAudio = processMultimodalWAV(buffer, {
    kind: "audio",
    sourceIndex: 0,
  }, { present: false, error: null, timeline: null });
  if (routeAudio !== result.base64Audio) {
    throw new Error("Route/shared processing differ");
  }
  const output = decodeBase64(routeAudio);
  const outputHeader = parseWavHeader(output.buffer as ArrayBuffer);
  const outputSamples = extractSamplesAsFloat32(
    output.buffer as ArrayBuffer,
    outputHeader,
  );
  // Independently locate the exact contiguous input region returned by the
  // production trimmer. A unique match is required before reporting its offset.
  const trimmed = trimSilence(inputSamples, header.sampleRate);
  const offsets: number[] = [];
  for (
    let offset = 0;
    offset <= inputSamples.length - trimmed.length;
    offset++
  ) {
    if (
      inputSamples[offset] !== trimmed[0] ||
      inputSamples[offset + trimmed.length - 1] !== trimmed[trimmed.length - 1]
    ) continue;
    let equal = true;
    for (let j = 0; j < trimmed.length; j++) {
      if (inputSamples[offset + j] !== trimmed[j]) {
        equal = false;
        break;
      }
    }
    if (equal) offsets.push(offset);
  }
  if (offsets.length !== 1) {
    throw new Error(`Ambiguous trim boundary: ${caseId}`);
  }
  const trimStart = offsets[0];
  const trimEnd = trimStart + trimmed.length;
  const outputFile = `${caseId}-processed.wav`;
  await Deno.writeFile(`${destination}/${outputFile}`, output, { mode: 0o600 });
  cases.push({
    caseId,
    input: {
      file,
      sha256: await hash(bytes),
      byteLength: bytes.length,
      sampleRate: header.sampleRate,
      channels: header.numChannels,
      bitsPerSample: header.bitsPerSample,
      durationSeconds: inputSamples.length / header.sampleRate,
      ...metrics(inputSamples),
    },
    output: {
      file: outputFile,
      sha256: await hash(output),
      byteLength: output.length,
      sampleRate: outputHeader.sampleRate,
      channels: outputHeader.numChannels,
      bitsPerSample: outputHeader.bitsPerSample,
      durationSeconds: outputSamples.length / outputHeader.sampleRate,
      ...metrics(outputSamples),
    },
    trim: {
      startSample: trimStart,
      endSampleExclusive: trimEnd,
      removedLeadingSeconds: trimStart / header.sampleRate,
      removedTrailingSeconds: (inputSamples.length - trimEnd) /
        header.sampleRate,
      retainedSampleCount: trimmed.length,
    },
    routeMatchesSharedProcessor: true,
    runtime: { firstLocalCallMilliseconds, ...runtime },
    previousOutput: baseline.cases.find((c: { caseId: string }) =>
      c.caseId === caseId
    ).output,
    restoredSourceTailSamples: trimmed.length -
      baseline.cases.find((c: { caseId: string }) => c.caseId === caseId).trim
        .retainedSampleCount,
  });
}
const synthetic = [];
for (const frequencyHz of [1000, 12000]) {
  const samples = Float32Array.from(
    { length: 88200 },
    (_, i) => 0.5 * Math.sin(2 * Math.PI * frequencyHz * i / 44100),
  );
  const input = encodeWav16(samples, 44100);
  const output = decodeBase64(
    processMultimodalWAV(input.buffer as ArrayBuffer, undefined, {
      present: false,
      error: null,
      timeline: null,
    }),
  );
  const header = parseWavHeader(output.buffer as ArrayBuffer);
  const decoded = extractSamplesAsFloat32(output.buffer as ArrayBuffer, header);
  const amplitudes = [];
  for (let candidate = 500; candidate <= 7500; candidate += 500) {
    let sine = 0, cosine = 0;
    for (let i = 0; i < decoded.length; i++) {
      const phase = 2 * Math.PI * candidate * i / header.sampleRate;
      sine += decoded[i] * Math.sin(phase);
      cosine += decoded[i] * Math.cos(phase);
    }
    amplitudes.push({
      frequencyHz: candidate,
      amplitude: 2 * Math.hypot(sine, cosine) / decoded.length,
    });
  }
  amplitudes.sort((a, b) => b.amplitude - a.amplitude);
  synthetic.push({
    sourceFrequencyHz: frequencyHz,
    previousStrongestTestedTone:
      baseline.synthetic.find((s: { sourceFrequencyHz: number }) =>
        s.sourceFrequencyHz === frequencyHz
      ).strongestTestedTone,
    toneAmplitudes: amplitudes,
    sourceAmplitude: 0.5,
    sourceSampleRate: 44100,
    durationSeconds: 2,
    outputSampleRate: header.sampleRate,
    output: metrics(decoded),
    strongestTestedTone: amplitudes[0],
    testedFrequencyGrid: "500..7500 Hz in 500 Hz steps",
    sourceSHA256: await hash(input),
    outputSHA256: await hash(output),
  });
}
const sourceFiles = [
  "_shared/audioProcessing.ts",
  "audio-spec/wav.ts",
  "audio-spec/resample.ts",
  "_shared/mediaBudgets.ts",
  "identify-multimodal/audio.ts",
  "identify-multimodal/provider.ts",
  "_shared/ai/geminiRequest.ts",
];
const sourceHashes = [];
for (const file of sourceFiles) {
  sourceHashes.push({
    path: `services/supabase/functions/${file}`,
    sha256: await hash(
      await Deno.readFile(
        new URL(
          `../../../../services/supabase/functions/${file}`,
          import.meta.url,
        ),
      ),
    ),
  });
}
const runtimeFixtures = [];
for (
  const [name, sampleRate, frames, consecutiveClips] of [
    ["native_15_second_pair", 44100, 44100 * 15, 2],
    ["max_source_44100_pair", 44100, Math.floor((2700000 - 44) / 2), 2],
    ["max_source_48000_pair", 48000, Math.floor((2700000 - 44) / 2), 2],
    ["max_source_96000_pair", 96000, Math.floor((2700000 - 44) / 2), 2],
    ["max_output_8000_pair", 8000, Math.floor((2700000 - 44) / 4), 2],
  ] as const
) {
  const input = encodeWav16(
    Float32Array.from(
      { length: frames },
      (_, i) => .25 * Math.sin(2 * Math.PI * 1000 * i / sampleRate),
    ),
    sampleRate,
  );
  const work = () => {
    for (let i = 0; i < consecutiveClips; i++) {
      processWavBuffer(input.buffer as ArrayBuffer);
    }
  };
  runtimeFixtures.push({
    name,
    sampleRate,
    sourceFramesPerClip: frames,
    sourceBytesPerClip: input.byteLength,
    consecutiveClips,
    ...timing(work),
  });
}
const unchangedOwners = [
  "identify-multimodal/audio.ts",
  "identify-multimodal/provider.ts",
  "_shared/ai/geminiRequest.ts",
];
for (const owner of unchangedOwners) {
  const path = `services/supabase/functions/${owner}`;
  if (
    sourceHashes.find((entry) => entry.path === path)?.sha256 !==
      baseline.sourceHashes.find((entry: { path: string }) =>
        entry.path === path
      )?.sha256
  ) throw new Error(`Unexpected provider/audio routing change: ${owner}`);
}
const report = {
  schemaVersion: 1,
  mode: "offline_candidate_actual_processor",
  createdAt: new Date().toISOString(),
  sourceFreezeSHA256: expectedFreeze,
  verifiedSourceFileCount: freeze.files.length,
  previousVerificationFreezeSHA256: expectedPreviousFreeze,
  verifiedPreviousFileCount: previousFreeze.files.length,
  algorithm: {
    targetSampleRate: 16000,
    filter: "Blackman-windowed sinc",
    radiusAtLowerRate: 32,
    cutoffNyquistRatio: 0.9,
    fractionalPhases: 128,
    boundary: "endpoint replication",
    outputLength: "floor(inputFrames * outputRate / inputRate)",
  },
  runtimeEnvironment: {
    deno: Deno.version.deno,
    architecture: Deno.build.arch,
    os: Deno.build.os,
    clock: "performance.now wall time; no network/provider work",
    interpretation:
      "local machine measurements, not hosted CPU usage or end-to-end inference latency",
  },
  runtimeFixtures,
  liveProviderCalls: 0,
  sourceHashes,
  cases,
  synthetic,
  limits: [
    "Local reprocessing; historical live inference bytes and private context were not retained.",
    "Synthetic tone comparison measures anti-aliasing, not species accuracy or the cause of historical disagreements.",
    "The 16 kHz output still cannot preserve source frequencies above 8 kHz; the transition band begins below that.",
    "No human listening assessment of the newly processed clips or hosted CPU measurement is claimed.",
    "No expected species labels or production responses are inputs to this analysis.",
  ],
};
await Deno.writeTextFile(
  `${destination}/analysis.json`,
  JSON.stringify(report, null, 2) + "\n",
  { mode: 0o600 },
);
console.log(JSON.stringify({
  cases: cases.map((c) => ({
    caseId: c.caseId,
    before: c.input.durationSeconds,
    after: c.output.durationSeconds,
    leadingRemoved: c.trim.removedLeadingSeconds,
    trailingRemoved: c.trim.removedTrailingSeconds,
  })),
  synthetic,
  runtimeFixtures,
  sourceVerified: freeze.files.length,
}));
