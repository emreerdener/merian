import {
  validateAndTransformWav,
  WavPreparationRejection,
} from "./wav-validation-bootstrap.ts";
import { processWavBuffer } from "../../services/supabase/functions/_shared/audioProcessing.ts";

function assert(value: unknown): asserts value {
  if (!value) throw new Error("assertion failed");
}
function equal(actual: unknown, expected: unknown) {
  assert(JSON.stringify(actual) === JSON.stringify(expected));
}
function wave(format = 1, channels = 1, rate = 8_000, frames = rate) {
  const width = format === 1 ? 2 : 4;
  const bytes = new Uint8Array(44 + frames * channels * width);
  bytes.set(new TextEncoder().encode("RIFF"));
  bytes.set(new TextEncoder().encode("WAVEfmt "), 8);
  bytes.set(new TextEncoder().encode("data"), 36);
  const view = new DataView(bytes.buffer);
  view.setUint32(4, bytes.length - 8, true);
  view.setUint32(16, 16, true);
  view.setUint16(20, format, true);
  view.setUint16(22, channels, true);
  view.setUint32(24, rate, true);
  view.setUint32(28, rate * channels * width, true);
  view.setUint16(32, channels * width, true);
  view.setUint16(34, width * 8, true);
  view.setUint32(40, bytes.length - 44, true);
  for (let offset = 44; offset < bytes.length; offset += width) {
    if (width === 2) view.setInt16(offset, 8_192, true);
    else view.setFloat32(offset, 0.25, true);
  }
  return bytes;
}

Deno.test("validated adapter copies exact view before validation and transform", () => {
  const bytes = wave();
  const surrounding = new Uint8Array(bytes.length + 30).fill(255);
  surrounding.set(bytes, 13);
  let calls = 0;
  const actual = validateAndTransformWav(
    surrounding.subarray(13, 13 + bytes.length),
    false,
    (buffer, rate, options) => {
      calls++;
      assert(buffer !== surrounding.buffer);
      equal(buffer.byteLength, bytes.length);
      equal(rate, 16_000);
      equal(options, { preserveSourceWhenTrimmedTooShort: false });
      assert(Object.isFrozen(options));
      surrounding.fill(0); // Caller mutation cannot change the copied source.
      equal([...new Uint8Array(buffer)], [...bytes]);
      return processWavBuffer(buffer, rate, options);
    },
  );
  equal(calls, 1);
  equal([...actual.source], [...bytes]);
  equal(actual.result, processWavBuffer(bytes.buffer));
});

Deno.test("validated adapter rejects malformed structure before any transform call", () => {
  const badSize = wave();
  new DataView(badSize.buffer).setUint32(4, 0, true);
  // The historical parser tolerates this input: eventual transform failure
  // alone cannot prove validation ran first.
  assert(processWavBuffer(badSize.buffer).encodedByteLength > 0);
  const badFrame = wave();
  new DataView(badFrame.buffer).setUint16(32, 3, true);
  const nonfinite = wave(3, 2);
  new DataView(nonfinite.buffer).setFloat32(48, NaN, true);
  const shared = new Uint8Array(new SharedArrayBuffer(wave().length));
  shared.set(wave());
  for (
    const source of [
      badSize,
      badFrame,
      nonfinite,
      new Uint8Array(2_700_001),
      shared as unknown as Uint8Array<ArrayBuffer>,
    ]
  ) {
    let calls = 0;
    try {
      validateAndTransformWav(source, true, () => {
        calls++;
        throw new Error("must not execute");
      });
      throw new Error("accepted invalid input");
    } catch (error) {
      assert(error instanceof WavPreparationRejection);
      equal(error.stage, "validation");
    }
    equal(calls, 0);
  }
});

Deno.test("validated adapter preserves existing PCM/float output and video fallback option", () => {
  for (const format of [1, 3]) {
    for (const channels of [1, 2, 3]) {
      const bytes = wave(format, channels);
      for (const preserve of [false, true]) {
        equal(
          validateAndTransformWav(bytes, preserve, processWavBuffer).result,
          processWavBuffer(bytes.buffer, 16_000, {
            preserveSourceWhenTrimmedTooShort: preserve,
          }),
        );
      }
    }
  }
  const shortSound = wave(1, 1, 16_000);
  shortSound.fill(0, 44);
  for (let i = 7_000; i < 7_300; i++) {
    new DataView(shortSound.buffer).setInt16(44 + i * 2, 8_192, true);
  }
  try {
    validateAndTransformWav(shortSound, false, processWavBuffer);
    throw new Error("short trimmed sound accepted");
  } catch (error) {
    assert(error instanceof WavPreparationRejection);
    equal(error.stage, "transform");
  }
  const kept = validateAndTransformWav(shortSound, true, processWavBuffer);
  equal(
    kept.result,
    processWavBuffer(shortSound.buffer, 16_000, {
      preserveSourceWhenTrimmedTooShort: true,
    }),
  );
  equal(kept.result.trimmedSampleCount, 16_000);
  equal(kept.result.originalSampleCount, 16_000);
});

Deno.test("validated adapter never relabels unexpected transform crashes", () => {
  for (
    const error of [
      new TypeError("decoder defect"),
      new TypeError(
        "Audio too short to identify. Please record a longer clip.",
      ),
      new Error("unexpected"),
      new RangeError("allocation"),
    ]
  ) {
    try {
      validateAndTransformWav(wave(), false, () => {
        throw error;
      });
      throw new Error("unexpected success");
    } catch (actual) {
      assert(actual === error);
      assert(!(actual instanceof WavPreparationRejection));
    }
  }
});

Deno.test("validated adapter rejects invalid options without a structural receipt", () => {
  let calls = 0;
  try {
    validateAndTransformWav(wave(), 1 as unknown as boolean, () => {
      calls++;
      throw new Error("must not execute");
    });
    throw new Error("unexpected success");
  } catch (error) {
    assert(error instanceof TypeError);
    assert(!(error instanceof WavPreparationRejection));
  }
  equal(calls, 0);
});
