import { assertEquals, assertNotEquals, assertThrows } from "@std/assert";
import { encodeWav16 } from "../functions/audio-spec/wav.ts";
import { processMultimodalWAV } from "../functions/identify-multimodal/audio.ts";
import { decodeBase64 } from "../functions/_shared/encoding.ts";
import {
  AUDIO_COMPARISON_ARMS,
  comparisonAudio,
  prepareAudioComparisonPair,
} from "./identification_evaluation/audioComparison.ts";

function source(frames = 44100) {
  return encodeWav16(
    Float32Array.from(
      { length: frames },
      (_, i) => 0.5 * Math.sin(2 * Math.PI * 12000 * i / 44100),
    ),
    44100,
  );
}

Deno.test("audio arms preserve current route bytes and expose both historical DSP differences", () => {
  const bytes = source(44100 + 828);
  const old = comparisonAudio(bytes, AUDIO_COMPARISON_ARMS[0]);
  const current = comparisonAudio(bytes, AUDIO_COMPARISON_ARMS[1]);
  assertEquals(old.length, 44 + 16000 * 2); // Historical incomplete window was dropped.
  assertEquals(current.length, 44 + Math.floor(44928 * 16000 / 44100) * 2);
  assertEquals(
    current,
    decodeBase64(
      processMultimodalWAV(new Uint8Array(bytes).buffer, {
        kind: "audio",
        sourceIndex: 0,
      }, { present: false, error: null, timeline: null }),
    ),
  );
  const rms = (wav: Uint8Array) => {
    const view = new DataView(wav.buffer, wav.byteOffset, wav.byteLength);
    let sum = 0, count = 0;
    for (let offset = 2044; offset < wav.length - 2000; offset += 2) {
      sum += (view.getInt16(offset, true) / 32768) ** 2;
      count++;
    }
    return Math.sqrt(sum / count);
  };
  assertNotEquals(old, current);
  assertEquals(rms(current) < rms(old) / 1000, true);
});

Deno.test("audio pair freezes identical non-audio requests and different processed bytes", async () => {
  const pair = await prepareAudioComparisonPair(source());
  assertEquals(pair, await prepareAudioComparisonPair(source()));
  assertEquals(pair.arms.map((a) => a.arm), [...AUDIO_COMPARISON_ARMS]);
  const [old, current] = pair.arms;
  assertEquals(
    old.requestWithoutAudioSha256,
    current.requestWithoutAudioSha256,
  );
  assertEquals(old.policySha256, current.policySha256);
  assertEquals(old.model, "gemini-2.5-pro");
  assertEquals(old.generation, current.generation);
  assertNotEquals(old.processedWavSha256, current.processedWavSha256);
  assertNotEquals(old.providerRequestSha256, current.providerRequestSha256);
  assertEquals(JSON.stringify(pair).includes("inlineData"), false);
});

Deno.test("historical DSP is bounded to canonical standalone comparison inputs", () => {
  for (const arm of AUDIO_COMPARISON_ARMS) {
    assertThrows(() => comparisonAudio(new Uint8Array(), arm));
    assertThrows(() => comparisonAudio(source(44100 * 15 + 1), arm));
    assertThrows(() =>
      comparisonAudio(encodeWav16(new Float32Array(16000), 16000), arm)
    );
    assertThrows(() => comparisonAudio(source(100), arm));
  }
  // A typed caller cannot select an unrecognized or future processor silently.
  assertThrows(() =>
    comparisonAudio(source(), "future" as typeof AUDIO_COMPARISON_ARMS[number])
  );
});
