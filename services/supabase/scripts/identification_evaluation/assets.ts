import type { MultimodalAIRequest } from "../../functions/_shared/ai/contracts.ts";
import { encodeBase64 } from "../../functions/_shared/encoding.ts";
import { MEDIA_BUDGETS } from "../../functions/_shared/mediaBudgets.ts";
import { processMultimodalWAV } from "../../functions/identify-multimodal/audio.ts";
import type {
  AudioMediaDescriptor,
  VisualMediaDescriptor,
} from "../../functions/identify-multimodal/capturedMedia.ts";
import { buildMultimodalAIRequest } from "../../functions/identify-multimodal/provider.ts";
import { fingerprintBytes } from "./evidence.ts";
import { containedPath, readBytes } from "./files.ts";
import {
  parseEvaluationInput,
  requireCondition as check,
} from "./validation.ts";

const ascii = (bytes: Uint8Array, start: number, length: number) =>
  String.fromCharCode(...bytes.subarray(start, start + length));
const dimensions = (w: number, h: number) =>
  check(
    w > 0 && h > 0 && w <= 8192 && h <= 8192 && w * h <= 32_000_000,
    "invalid_media",
  );

export function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (const b of bytes) {
    crc ^= b;
    for (let i = 0; i < 8; i++) crc = crc >>> 1 ^ (crc & 1 ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
/** Container/metadata checks, not a pixel decoder. Curation must decode and
 * review the final prepared image before hashing; no source bytes are rewritten.
 * Reject embedded text, EXIF, XMP, comments, animation and unknown chunks.
 */
export function validateImage(bytes: Uint8Array, mime: string): void {
  check(bytes.length >= 20, "invalid_media");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (mime === "image/png") {
    check(
      bytes.slice(0, 8).every((b, i) =>
        b === [137, 80, 78, 71, 13, 10, 26, 10][i]
      ),
      "invalid_media",
    );
    let p = 8, header = false, data = false, ended = false;
    while (p < bytes.length) {
      check(p + 12 <= bytes.length && !ended, "invalid_media");
      const n = view.getUint32(p), kind = ascii(bytes, p + 4, 4);
      check(
        p + n + 12 <= bytes.length &&
          ["IHDR", "PLTE", "tRNS", "IDAT", "IEND"].includes(kind),
        "invalid_media",
      );
      check(
        crc32(bytes.subarray(p + 4, p + 8 + n)) === view.getUint32(p + 8 + n),
        "invalid_media",
      );
      if (!header) {
        check(kind === "IHDR" && n === 13, "invalid_media");
        dimensions(view.getUint32(p + 8), view.getUint32(p + 12));
        check(
          [1, 2, 4, 8, 16].includes(bytes[p + 16]) &&
            [0, 2, 3, 4, 6].includes(bytes[p + 17]) && bytes[p + 18] === 0 &&
            bytes[p + 19] === 0 && bytes[p + 20] <= 1,
          "invalid_media",
        );
        header = true;
      } else check(kind !== "IHDR", "invalid_media");
      if (kind === "IDAT") {
        check(n > 0, "invalid_media");
        data = true;
      }
      if (kind === "IEND") {
        check(n === 0 && data, "invalid_media");
        ended = true;
      }
      p += n + 12;
    }
    check(ended, "invalid_media");
  } else if (mime === "image/webp") {
    check(
      ascii(bytes, 0, 4) === "RIFF" && ascii(bytes, 8, 4) === "WEBP" &&
        view.getUint32(4, true) + 8 === bytes.length,
      "invalid_media",
    );
    let p = 12, images = 0;
    while (p < bytes.length) {
      check(p + 8 <= bytes.length, "invalid_media");
      const kind = ascii(bytes, p, 4),
        n = view.getUint32(p + 4, true),
        d = p + 8;
      check(
        d + n + (n % 2) <= bytes.length &&
          ["VP8X", "ALPH", "VP8 ", "VP8L"].includes(kind),
        "invalid_media",
      );
      if (kind === "VP8X") {
        check(
          p === 12 && n === 10 && (bytes[d] & ~0x10) === 0 &&
            bytes[d + 1] === 0 && bytes[d + 2] === 0 && bytes[d + 3] === 0,
          "invalid_media",
        );
        dimensions(
          1 + bytes[d + 4] + 256 * bytes[d + 5] + 65536 * bytes[d + 6],
          1 + bytes[d + 7] + 256 * bytes[d + 8] + 65536 * bytes[d + 9],
        );
      } else if (kind === "VP8 ") {
        check(
          n >= 10 && bytes[d + 3] === 0x9d && bytes[d + 4] === 1 &&
            bytes[d + 5] === 0x2a && !(bytes[d] & 1),
          "invalid_media",
        );
        dimensions(
          view.getUint16(d + 6, true) & 0x3fff,
          view.getUint16(d + 8, true) & 0x3fff,
        );
        images++;
      } else if (kind === "VP8L") {
        check(
          n >= 5 && bytes[d] === 0x2f && (bytes[d + 4] >>> 5) === 0,
          "invalid_media",
        );
        const bits = view.getUint32(d + 1, true);
        dimensions((bits & 0x3fff) + 1, ((bits >>> 14) & 0x3fff) + 1);
        images++;
      }
      p = d + n + (n % 2);
    }
    check(images === 1, "invalid_media");
  } else {
    check(
      mime === "image/jpeg" && bytes[0] === 255 && bytes[1] === 216,
      "invalid_media",
    );
    let p = 2, frame = false, scan = false, ended = false;
    while (p < bytes.length) {
      check(bytes[p++] === 255, "invalid_media");
      while (bytes[p] === 255) p++;
      const marker = bytes[p++];
      if (marker === 217) {
        ended = true;
        break;
      }
      check(
        [0xc0, 0xc1, 0xc2, 0xc4, 0xdb, 0xdd, 0xda, 0xe0, 0xee].includes(
          marker,
        ) && p + 2 <= bytes.length,
        "invalid_media",
      );
      const n = view.getUint16(p);
      check(n >= 2 && p + n <= bytes.length, "invalid_media");
      if (marker === 0xe0) {
        check(
          n === 16 && ascii(bytes, p + 2, 5) === "JFIF\0" &&
            bytes[p + 14] === 0 && bytes[p + 15] === 0,
          "invalid_media",
        );
      }
      if (marker === 0xee) {
        check(n === 14 && ascii(bytes, p + 2, 5) === "Adobe", "invalid_media");
      }
      if ([0xc0, 0xc1, 0xc2].includes(marker)) {
        check(!frame && n >= 11, "invalid_media");
        dimensions(view.getUint16(p + 5), view.getUint16(p + 3));
        frame = true;
      }
      p += n;
      if (marker === 0xda) {
        check(frame, "invalid_media");
        scan = true;
        while (p < bytes.length) {
          if (bytes[p] !== 255) {
            p++;
            continue;
          }
          const next = bytes[p + 1];
          if (next === 0 || next >= 0xd0 && next <= 0xd7) {
            p += 2;
            continue;
          }
          break;
        }
      }
    }
    check(frame && scan && ended && p === bytes.length, "invalid_media");
  }
}
export function validateWavContainer(bytes: Uint8Array): void {
  check(bytes.length >= 44, "invalid_media");
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  check(
    ascii(bytes, 0, 4) === "RIFF" && ascii(bytes, 8, 4) === "WAVE" &&
      v.getUint32(4, true) + 8 === bytes.length,
    "invalid_media",
  );
  let p = 12, fmt = false, data = false, blockAlign = 0;
  while (p < bytes.length) {
    check(p + 8 <= bytes.length, "invalid_media");
    const kind = ascii(bytes, p, 4), n = v.getUint32(p + 4, true);
    check(p + n + 8 + (n % 2) <= bytes.length, "invalid_media");
    if (kind === "fmt ") {
      check(
        !fmt && !data && n === 16 && v.getUint16(p + 8, true) === 1,
        "invalid_media",
      );
      const channels = v.getUint16(p + 10, true),
        sampleRate = v.getUint32(p + 12, true);
      blockAlign = v.getUint16(p + 20, true);
      check(
        channels >= 1 && channels <= 2 && sampleRate >= 8000 &&
          sampleRate <= 96000 && v.getUint16(p + 22, true) === 16 &&
          blockAlign === channels * 2 &&
          v.getUint32(p + 16, true) === sampleRate * blockAlign,
        "invalid_media",
      );
      fmt = true;
    } else {
      check(
        kind === "data" && fmt && !data && n > 0 && n % blockAlign === 0,
        "invalid_media",
      );
      data = true;
    }
    p += n + 8 + (n % 2);
  }
  check(fmt && data, "invalid_media");
}

/** Every asset is validated and included; never accept a partially loaded case. */
export async function prepareEvidence(
  root: string,
  inputValue: unknown,
): Promise<MultimodalAIRequest> {
  const input = parseEvaluationInput(inputValue);
  const images = input.assets.filter((a) =>
    a.kind === "image" || a.kind === "video_frame"
  );
  const audio = input.assets.filter((a) =>
    a.kind === "audio" || a.kind === "video_audio"
  );
  check(
    images.length <= MEDIA_BUDGETS.maxImageCount &&
      audio.length <= MEDIA_BUDGETS.maxAudioClips &&
      input.clips.length <= MEDIA_BUDGETS.maxStagedVideoFiles,
    "invalid_media",
  );
  check(
    images.reduce((n, a) => n + a.byteLength, 0) <=
      MEDIA_BUDGETS.maxImageRawBytes,
    "invalid_media",
  );
  const visualMediaItems: VisualMediaDescriptor[] = [],
    audioMediaItems: AudioMediaDescriptor[] = [];
  const imageBase64s: string[] = [], processedAudios: string[] = [];
  for (const asset of input.assets) {
    const visual = asset.kind === "image" || asset.kind === "video_frame";
    const bytes = await readBytes(
      await containedPath(root, asset.path),
      visual ? MEDIA_BUDGETS.maxImageRawBytes : MEDIA_BUDGETS.maxAudioRawBytes,
    );
    check(
      bytes.length === asset.byteLength &&
        await fingerprintBytes(bytes) === asset.sha256,
      "invalid_media",
    );
    if (visual) {
      validateImage(bytes, asset.mimeType);
      imageBase64s.push(encodeBase64(bytes));
      visualMediaItems.push(
        asset.kind === "image"
          ? { kind: asset.kind, sourceIndex: asset.sourceIndex }
          : {
            kind: asset.kind,
            clipIndex: asset.clipIndex,
            frameIndex: asset.frameIndex,
          },
      );
    } else {
      validateWavContainer(bytes);
      const descriptor: AudioMediaDescriptor = asset.kind === "audio"
        ? { kind: asset.kind, sourceIndex: asset.sourceIndex }
        : { kind: asset.kind, clipIndex: asset.clipIndex };
      audioMediaItems.push(descriptor);
      processedAudios.push(
        processMultimodalWAV(new Uint8Array(bytes).buffer, descriptor, {
          present: true,
          error: null,
          timeline: input.clips.map((c) => ({
            kind: "video",
            clipIndex: c.clipIndex,
          })),
        }),
      );
      check(
        processedAudios.at(-1)!.length <= MEDIA_BUDGETS.maxAudioBase64Chars,
        "invalid_media",
      );
    }
  }
  const request = buildMultimodalAIRequest({
    observationEvidenceTexts: [...input.observationTexts],
    visualMediaItems,
    imageBase64s,
    imageMimeType: images[0]?.mimeType ?? "image/jpeg",
    processedAudios,
    audioMediaItems,
    processedAudioInputIndexes: audio.map((_, i) => i),
    hasVideoAudio: audio.some((a) => a.kind === "video_audio"),
    capture: {
      hasVideo: input.clips.length > 0,
      videoClipCount: input.clips.length,
      declaredVideoFrameCount: input.clips.reduce(
        (n, c) => n + c.declaredFrameCount,
        0,
      ),
      videoInferenceFrameCount: images.filter((a) =>
        a.kind === "video_frame"
      ).length,
    },
    telemetry: { safeGpsLat: null, safeGpsLon: null, ...input.context },
  });
  check(
    new TextEncoder().encode(JSON.stringify(request)).length <=
      MEDIA_BUDGETS.maxMultimodalJsonBodyBytes,
    "invalid_media",
  );
  return request;
}
