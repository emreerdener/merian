import { assertEquals, assertThrows } from "@std/assert";
import { encodeWav16, parseWavHeader } from "../audio-spec/wav.ts";
import { decodeBase64 } from "../_shared/encoding.ts";
import { processMultimodalWAV } from "./audio.ts";
import {
  type AudioMediaDescriptor,
  validateOwnerMediaTimeline,
} from "./capturedMedia.ts";

function fixture(seconds = 5, activeSeconds = 0.08): ArrayBuffer {
  const samples = new Float32Array(44_100 * seconds);
  for (
    let index = 0;
    index < Math.min(samples.length, 44_100 * activeSeconds);
    index++
  ) {
    samples[index] = 0.2 * Math.sin(2 * Math.PI * 880 * index / 44_100);
  }
  return encodeWav16(samples, 44_100).buffer as ArrayBuffer;
}

function timeline(descriptors: AudioMediaDescriptor[], rawTimeline: unknown) {
  return validateOwnerMediaTimeline({
    rawTimeline,
    visualMediaItems: [{ kind: "video_frame", clipIndex: 0, frameIndex: 0 }],
    resolvedImageCount: 1,
    audioMediaItems: descriptors,
    resolvedAudioCount: descriptors.length,
    videoCount: 1,
    observationContextCount: 0,
  });
}

const companion: AudioMediaDescriptor = { kind: "video_audio", clipIndex: 0 };
const standalone: AudioMediaDescriptor = { kind: "audio", sourceIndex: 0 };
const validTimeline = timeline([companion, standalone], [
  { kind: "video", clipIndex: 0 },
  { kind: "audio", sourceIndex: 0, audioInputIndex: 1 },
]);

Deno.test("validated video companion retains sparse sound and its source context", () => {
  assertEquals(validTimeline.error, null);
  const output = decodeBase64(
    processMultimodalWAV(fixture(), companion, validTimeline),
  );
  const header = parseWavHeader(output.buffer as ArrayBuffer);
  assertEquals(header.sampleRate, 16_000);
  assertEquals(header.numChannels, 1);
  assertEquals(header.dataLength, 5 * 16_000 * 2);
  // A standalone clip in the same request keeps the strict duration policy.
  assertThrows(
    () => processMultimodalWAV(fixture(), standalone, validTimeline),
    Error,
    "Audio too short",
  );
});

Deno.test("unproven companion descriptors cannot enable sparse audio fallback", () => {
  for (
    const validation of [
      timeline([companion], undefined),
      timeline([companion], []),
      timeline([{ kind: "video_audio", clipIndex: 9 }], [{
        kind: "video",
        clipIndex: 0,
      }]),
    ]
  ) {
    assertThrows(
      () => processMultimodalWAV(fixture(), companion, validation),
      Error,
      "Audio too short",
    );
  }
  assertThrows(
    () => processMultimodalWAV(fixture(), undefined, validTimeline),
    Error,
    "Audio too short",
  );
});

Deno.test("video fallback still rejects truly short and malformed WAV sources", () => {
  assertThrows(
    () => processMultimodalWAV(fixture(0.08), companion, validTimeline),
    Error,
    "Audio too short",
  );
  assertThrows(() =>
    processMultimodalWAV(new ArrayBuffer(12), companion, validTimeline)
  );
  assertThrows(() =>
    processMultimodalWAV(fixture().slice(0, 100), companion, validTimeline)
  );
});

Deno.test("ordinary trimming and complete silence preserve existing behavior", () => {
  for (const descriptor of [companion, standalone]) {
    const trimmed = decodeBase64(
      processMultimodalWAV(fixture(5, 1), descriptor, validTimeline),
    );
    assertEquals(
      parseWavHeader(trimmed.buffer as ArrayBuffer).dataLength,
      1.04 * 16_000 * 2,
    );
    const silent = decodeBase64(
      processMultimodalWAV(fixture(5, 0), descriptor, validTimeline),
    );
    assertEquals(
      parseWavHeader(silent.buffer as ArrayBuffer).dataLength,
      5 * 16_000 * 2,
    );
  }
});
