import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  createAudioSpectrogramThumbnail,
  type R2Config,
  renderAudioSpectrogramPng,
} from "./audioSpectrogram.ts";

Deno.test("renderAudioSpectrogramPng renders iOS-compatible FFT dimensions", async () => {
  const wav = makePcm16Wav(4_096, 48_000, 2_000);
  const png = await renderAudioSpectrogramPng(wav);
  assert(png);
  assertEquals(Array.from(png.subarray(0, 8)), [
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
  ]);
  const header = new DataView(png.buffer, png.byteOffset + 16, 8);
  assertEquals(header.getUint32(0), 2);
  assertEquals(header.getUint32(4), 128);
  const idatLength = new DataView(png.buffer, png.byteOffset + 33, 4)
    .getUint32(0);
  assertEquals(new TextDecoder().decode(png.subarray(37, 41)), "IDAT");
  const compressedBytes = png.slice(41, 41 + idatLength).buffer;
  const decompressed = await new Response(
    new Blob([compressedBytes]).stream().pipeThrough(
      new DecompressionStream("deflate"),
    ),
  ).arrayBuffer();
  assertEquals(decompressed.byteLength, 128 * (2 * 4 + 1));
});

Deno.test("createAudioSpectrogramThumbnail stores one deterministic PNG beside its audio", async () => {
  const wav = makePcm16Wav(2_048, 48_000, 1_500);
  let uploadedKey = "";
  let uploadedType = "";
  const url = await createAudioSpectrogramThumbnail(
    "https://media.merian.app/public_uploads/pro/user-id/clip.wav",
    {
      fetchMedia: () => Promise.resolve({ bytes: wav, mimeType: "audio/wav" }),
      getConfig: () => ({} as R2Config),
      headObject: () => Promise.resolve(new Response(null, { status: 404 })),
      putObject: (key, body, contentType) => {
        uploadedKey = key;
        uploadedType = contentType;
        assert(body.byteLength > 32);
        return Promise.resolve(new Response(null, { status: 200 }));
      },
    },
  );

  assert(url);
  assert(
    url.startsWith(
      "https://media.merian.app/public_uploads/pro/user-id/spectrogram-v1-",
    ),
  );
  assert(url.endsWith(".png"));
  assertEquals(uploadedKey, url.replace("https://media.merian.app/", ""));
  assertEquals(uploadedType, "image/png");
});

Deno.test("createAudioSpectrogramThumbnail reuses an existing deterministic asset", async () => {
  const wav = makePcm16Wav(2_048, 48_000, 800);
  let uploadCount = 0;
  const url = await createAudioSpectrogramThumbnail(
    "https://media.merian.app/public_uploads/free/user-id/clip.wav",
    {
      fetchMedia: () => Promise.resolve({ bytes: wav, mimeType: "audio/wav" }),
      getConfig: () => ({} as R2Config),
      headObject: () => Promise.resolve(new Response(null, { status: 200 })),
      putObject: () => {
        uploadCount += 1;
        return Promise.resolve(new Response(null, { status: 200 }));
      },
    },
  );

  assert(url?.includes("/spectrogram-v1-"));
  assertEquals(uploadCount, 0);
});

Deno.test("createAudioSpectrogramThumbnail leaves unsupported legacy codecs on the fallback", async () => {
  const result = await createAudioSpectrogramThumbnail(
    "https://media.merian.app/public_uploads/free/user-id/clip.m4a",
    {
      fetchMedia: () =>
        Promise.resolve({
          bytes: new ArrayBuffer(32),
          mimeType: "audio/mp4",
        }),
    },
  );
  assertEquals(result, null);
});

function makePcm16Wav(
  frameCount: number,
  sampleRate: number,
  frequency: number,
): ArrayBuffer {
  const dataLength = frameCount * 2;
  const buffer = new ArrayBuffer(44 + dataLength);
  const view = new DataView(buffer);
  writeAscii(view, 0, "RIFF");
  view.setUint32(4, 36 + dataLength, true);
  writeAscii(view, 8, "WAVE");
  writeAscii(view, 12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  writeAscii(view, 36, "data");
  view.setUint32(40, dataLength, true);
  for (let frame = 0; frame < frameCount; frame += 1) {
    const sample = Math.sin(2 * Math.PI * frequency * frame / sampleRate);
    view.setInt16(44 + frame * 2, Math.round(sample * 24_000), true);
  }
  return buffer;
}

function writeAscii(view: DataView, offset: number, value: string) {
  for (let index = 0; index < value.length; index += 1) {
    view.setUint8(offset + index, value.charCodeAt(index));
  }
}
