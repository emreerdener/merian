import { decodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";

export const MEDIA_BUDGETS = {
  maxImageCount: 5,
  maxImageRawBytes: 5 * 1024 * 1024,
  maxImageBase64Chars: 7 * 1024 * 1024,
  maxAudioClips: 2,
  maxAudioRawBytes: 2_700_000,
  maxAudioBase64Chars: 3_600_000,
  maxAudioJsonBodyBytes: 4 * 1024 * 1024,
  maxIdentifyJsonBodyBytes: 8 * 1024 * 1024,
  maxMultimodalJsonBodyBytes: 16 * 1024 * 1024,
  maxStagingFiles: 5,
  maxStagedAudioFiles: 2,
} as const;

export type StagingMediaKind = "image" | "audio";

export const STAGING_ALLOWED_CONTENT_TYPES: Record<
  StagingMediaKind,
  readonly string[]
> = {
  image: [
    "image/webp",
    "image/jpeg",
    "image/png",
    "image/heic",
    "image/heif",
  ],
  audio: ["audio/wav", "audio/mp4"],
};

export const MEDIA_BUDGET_ERRORS = {
  audioTooLarge: "Audio payload too large.",
  invalidAudioBase64: "Invalid audio encoding: malformed base64.",
  tooManyAudioClips: "Too many audio clips.",
  imageBase64TooLarge:
    "Payload Too Large: base64 payload exceeds 5 MB raw limit.",
  singleImageTooLarge:
    "Payload Too Large: A single image exceeds the 5MB limit.",
  combinedImagesTooLarge:
    "Payload Too Large: Combined images exceed 5MB limit.",
  requestBodyTooLarge: "Payload Too Large: request body exceeds media budget.",
} as const;

export interface MediaBudgetError {
  status: number;
  message: string;
}

export type StagingObjectKeyError = "path_traversal" | "wrong_user" | null;

function budgetError(status: number, message: string): MediaBudgetError {
  return { status, message };
}

function exactArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const buffer = bytes.buffer;
  if (
    buffer instanceof ArrayBuffer &&
    bytes.byteOffset === 0 &&
    bytes.byteLength === buffer.byteLength
  ) {
    return buffer;
  }
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

export function validateAudioClipCount(
  r2ClipCount: number,
  inlineClipCount: number,
): MediaBudgetError | null {
  return r2ClipCount + inlineClipCount > MEDIA_BUDGETS.maxAudioClips
    ? budgetError(413, MEDIA_BUDGET_ERRORS.tooManyAudioClips)
    : null;
}

export function validateInlineAudioBase64Budget(
  audioBase64: string,
): MediaBudgetError | null {
  return audioBase64.length > MEDIA_BUDGETS.maxAudioBase64Chars
    ? budgetError(413, MEDIA_BUDGET_ERRORS.audioTooLarge)
    : null;
}

export function validateRawAudioByteLength(
  byteLength: number,
): MediaBudgetError | null {
  return byteLength > MEDIA_BUDGETS.maxAudioRawBytes
    ? budgetError(413, MEDIA_BUDGET_ERRORS.audioTooLarge)
    : null;
}

export function decodeInlineAudioBase64(
  audioBase64: string,
): { buffer?: ArrayBuffer; error?: MediaBudgetError } {
  const lengthError = validateInlineAudioBase64Budget(audioBase64);
  if (lengthError) return { error: lengthError };

  let bytes: Uint8Array;
  try {
    bytes = decodeBase64(audioBase64);
  } catch {
    return {
      error: budgetError(400, MEDIA_BUDGET_ERRORS.invalidAudioBase64),
    };
  }

  const byteLengthError = validateRawAudioByteLength(bytes.byteLength);
  if (byteLengthError) return { error: byteLengthError };

  return { buffer: exactArrayBuffer(bytes) };
}

export function validateResponseContentLength(
  response: Response,
  maxBytes: number,
  message: string,
): MediaBudgetError | null {
  const contentLength = response.headers.get("content-length");
  if (contentLength === null) return null;

  const declaredBytes = Number(contentLength);
  return Number.isFinite(declaredBytes) && declaredBytes > maxBytes
    ? budgetError(413, message)
    : null;
}

export function validateRequestContentLength(
  request: Request,
  maxBytes: number,
  message = MEDIA_BUDGET_ERRORS.requestBodyTooLarge,
): MediaBudgetError | null {
  const contentLength = request.headers.get("content-length");
  if (contentLength === null) return null;

  const declaredBytes = Number(contentLength);
  return Number.isFinite(declaredBytes) && declaredBytes > maxBytes
    ? budgetError(413, message)
    : null;
}

export async function readResponseArrayBufferWithinBudget(
  response: Response,
  maxBytes: number,
  message: string,
): Promise<{ buffer?: ArrayBuffer; error?: MediaBudgetError }> {
  const headerError = validateResponseContentLength(
    response,
    maxBytes,
    message,
  );
  if (headerError) return { error: headerError };

  const buffer = await response.arrayBuffer();
  return buffer.byteLength > maxBytes
    ? { error: budgetError(413, message) }
    : { buffer };
}

export function validateStagingObjectKey(
  key: string,
  userId: string,
): StagingObjectKeyError {
  if (key.includes("..")) return "path_traversal";
  if (!key.startsWith(`staging/${userId}/`)) return "wrong_user";
  return null;
}
