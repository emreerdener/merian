import { decodeBase64 } from "./encoding.ts";

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
  maxStagingFiles: 6,
  maxStagedAudioFiles: 2,
  maxVideoRawBytes: 12 * 1024 * 1024,
  maxStagedVideoFiles: 1,
} as const;

export type StagingMediaKind = "image" | "audio" | "video";

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
  video: ["video/mp4"],
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
  videoTooLarge: "Video payload too large.",
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

  return await readStreamArrayBufferWithinBudget(
    response.body,
    maxBytes,
    message,
  );
}

export async function readStreamArrayBufferWithinBudget(
  stream: ReadableStream<Uint8Array> | null,
  maxBytes: number,
  message: string,
): Promise<{ buffer?: ArrayBuffer; error?: MediaBudgetError }> {
  if (!stream) return { buffer: new ArrayBuffer(0) };

  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;

  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      if (!value || value.byteLength === 0) continue;

      totalBytes += value.byteLength;
      if (totalBytes > maxBytes) {
        await reader.cancel();
        return { error: budgetError(413, message) };
      }

      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  return { buffer: exactArrayBuffer(bytes) };
}

export async function readRequestJsonWithinBudget<T>(
  request: Request,
  maxBytes: number,
  message = MEDIA_BUDGET_ERRORS.requestBodyTooLarge,
): Promise<{ value?: T; error?: MediaBudgetError }> {
  const headerError = validateRequestContentLength(request, maxBytes, message);
  if (headerError) return { error: headerError };

  const readResult = await readStreamArrayBufferWithinBudget(
    request.body,
    maxBytes,
    message,
  );
  if (readResult.error || !readResult.buffer) {
    return { error: readResult.error ?? budgetError(400, "Invalid JSON body") };
  }

  try {
    const raw = new TextDecoder().decode(readResult.buffer);
    return { value: JSON.parse(raw) as T };
  } catch {
    return { error: budgetError(400, "Invalid JSON body") };
  }
}

export function validateStagingObjectKey(
  key: string,
  userId: string,
): StagingObjectKeyError {
  if (key.includes("..")) return "path_traversal";
  if (!key.startsWith(`staging/${userId}/`)) return "wrong_user";
  return null;
}
