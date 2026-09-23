import { assert, assertEquals, assertThrows } from "@std/assert";
import { resampleBandlimited } from "./resample.ts";

function tone(rate: number, frequency: number, seconds = 0.5): Float32Array {
  return Float32Array.from(
    { length: Math.floor(rate * seconds) },
    (_, i) => 0.5 * Math.sin(2 * Math.PI * frequency * i / rate),
  );
}

// Exclude clip-boundary transients; separate DC/edge tests cover those samples.
function interiorRMS(samples: Float32Array, expected?: Float32Array): number {
  let sum = 0;
  for (let i = 128; i < samples.length - 128; i++) {
    const difference = samples[i] - (expected?.[i] ?? 0);
    sum += difference * difference;
  }
  return Math.sqrt(sum / (samples.length - 256));
}

Deno.test("resampling preserves useful-band tones, time alignment and duration", () => {
  for (const rate of [22_050, 32_000, 44_100, 48_000, 96_000]) {
    for (const frequency of [100, 1_000, 4_000, 6_000]) {
      const output = resampleBandlimited(
        tone(rate, frequency),
        rate,
        16_000,
        8_000,
      );
      assertEquals(output.length, 8_000);
      const expected = tone(16_000, frequency);
      assert(
        interiorRMS(output, expected) / interiorRMS(expected) < 0.003,
        `${rate} Hz source, ${frequency} Hz tone: gain/phase changed`,
      );
    }
  }
});

Deno.test("downsampling rejects out-of-band energy instead of aliasing it", () => {
  for (const rate of [44_100, 48_000, 96_000]) {
    for (const frequency of [8_200, 9_000, 12_000, 15_000, 20_000]) {
      const output = resampleBandlimited(
        tone(rate, frequency),
        rate,
        16_000,
        8_000,
      );
      // At least 60 dB rejection, measured independently from the FIR design.
      assert(
        interiorRMS(output) / (0.5 / Math.SQRT2) < 0.001,
        `${rate} Hz source, ${frequency} Hz tone: audible alias`,
      );
    }
  }
});

Deno.test("upsampling preserves the source band without time shift", () => {
  const output = resampleBandlimited(tone(8_000, 1_000), 8_000, 16_000, 8_000);
  const expected = tone(16_000, 1_000);
  assertEquals(output.length, expected.length);
  assert(interiorRMS(output, expected) / interiorRMS(expected) < 0.003);
});

Deno.test("resampling preserves silence and DC including both clip edges", () => {
  for (const level of [0, -0.75, 0.25]) {
    const input = new Float32Array(44_237).fill(level);
    const output = resampleBandlimited(input, 44_100, 16_000, 16_050);
    assertEquals(output.length, Math.floor(input.length * 16_000 / 44_100));
    assert(output.every((sample) => Math.abs(sample - level) < 0.000001));
  }
  const input = new Float32Array([0, 0.25, -0.75]);
  assertEquals(resampleBandlimited(input, 16_000, 16_000, 3), input);
  assertEquals(
    resampleBandlimited(new Float32Array(), 44_100, 16_000, 0).length,
    0,
  );
});

Deno.test("resampling rejects invalid rates, non-finite PCM and unbounded work", () => {
  for (const rate of [0, -1, NaN, Infinity, 44_100.5]) {
    assertThrows(() =>
      resampleBandlimited(new Float32Array(10), rate, 16_000, 100)
    );
    assertThrows(() =>
      resampleBandlimited(new Float32Array(10), 16_000, rate, 100)
    );
  }
  for (const sample of [NaN, Infinity, -Infinity]) {
    assertThrows(
      () => resampleBandlimited(new Float32Array([sample]), 16_000, 16_000, 1),
      Error,
      "non-finite PCM",
    );
  }
  assertThrows(
    () => resampleBandlimited(new Float32Array(1_000), 1, 16_000, 16_000),
    Error,
    "exceeds processing budget",
  );
  assertThrows(
    () =>
      resampleBandlimited(new Float32Array(250_000), 4_000_000, 16_000, 1_000),
    Error,
    "work exceeds processing budget",
  );
  assertThrows(
    () =>
      resampleBandlimited(new Float32Array(2_000_000), 44_100, 16_000, 800_000),
    Error,
    "work exceeds processing budget",
  );
});
