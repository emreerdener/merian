import { getR2Config } from "../aws.ts";
import { jsonResponse, logStructuredError } from "../edgeHandler.ts";
import { encodeBase64 } from "../encoding.ts";
import {
  decodeInlineAudioBase64,
  MEDIA_BUDGET_ERRORS,
  MEDIA_BUDGETS,
  readResponseArrayBufferWithinBudget,
  validateAudioClipCount,
  validateStagingObjectKey,
} from "../mediaBudgets.ts";

type R2Config = ReturnType<typeof getR2Config>;

interface ValidateImageR2ObjectKeysOptions {
  enforceOwnership: boolean;
  idorEvent: string;
  pathTraversalMessage?: string;
  wrongUserMessage?: string;
}

interface ResolveAudioBuffersOptions {
  userId: string;
  audioR2ObjectKeys?: string[];
  audioBase64s?: string[];
  idorEvent: string;
  r2FetchFailedEvent: string;
  pathTraversalMessage?: string;
  wrongUserMessage?: string;
  r2FetchError?: (response: Response, key: string) => {
    message: string;
    status: number;
  };
}

export function validateImageR2ObjectKeys(
  r2ObjectKeys: string[] | undefined,
  userId: string,
  options: ValidateImageR2ObjectKeysOptions,
): Response | null {
  if (!r2ObjectKeys || r2ObjectKeys.length === 0) return null;

  for (const r2ObjectKey of r2ObjectKeys) {
    const keyError = validateStagingObjectKey(r2ObjectKey, userId);
    if (keyError === "path_traversal") {
      return jsonResponse(
        {
          error: options.pathTraversalMessage ??
            "Bad Request: Path traversal detected.",
        },
        400,
      );
    }
    if (keyError === "wrong_user" && options.enforceOwnership) {
      logStructuredError(options.idorEvent, {
        user_id: userId,
        r2_object_key: r2ObjectKey,
      });
      return jsonResponse(
        {
          error: options.wrongUserMessage ??
            "Forbidden: r2ObjectKey does not belong to the requesting user.",
        },
        403,
      );
    }
  }

  return null;
}

export async function resolveAudioBuffers(
  options: ResolveAudioBuffersOptions,
): Promise<{
  audioBuffers: ArrayBuffer[];
  errorResponse?: Response;
  r2Config?: R2Config;
}> {
  const audioR2ObjectKeys = options.audioR2ObjectKeys ?? [];
  const audioBase64s = options.audioBase64s ?? [];
  const clipCountError = validateAudioClipCount(
    audioR2ObjectKeys.length,
    audioBase64s.length,
  );
  if (clipCountError) {
    return {
      audioBuffers: [],
      errorResponse: jsonResponse(
        { error: clipCountError.message },
        clipCountError.status,
      ),
    };
  }

  const audioBuffers: ArrayBuffer[] = [];
  for (const b64 of audioBase64s) {
    const decoded = decodeInlineAudioBase64(b64);
    if (decoded.error || !decoded.buffer) {
      return {
        audioBuffers: [],
        errorResponse: jsonResponse(
          {
            error: decoded.error?.message ??
              MEDIA_BUDGET_ERRORS.invalidAudioBase64,
          },
          decoded.error?.status ?? 400,
        ),
      };
    }
    audioBuffers.push(decoded.buffer);
  }

  let r2Config: R2Config | undefined;
  for (const audioR2ObjectKey of audioR2ObjectKeys) {
    const keyError = validateStagingObjectKey(
      audioR2ObjectKey,
      options.userId,
    );
    if (keyError === "path_traversal") {
      return {
        audioBuffers: [],
        errorResponse: jsonResponse(
          {
            error: options.pathTraversalMessage ??
              "Bad Request: Path traversal detected.",
          },
          400,
        ),
      };
    }
    if (keyError === "wrong_user") {
      logStructuredError(options.idorEvent, {
        user_id: options.userId,
        audio_r2_key: audioR2ObjectKey,
      });
      return {
        audioBuffers: [],
        errorResponse: jsonResponse(
          {
            error: options.wrongUserMessage ??
              "Forbidden: audioR2ObjectKey does not belong to the requesting user.",
          },
          403,
        ),
      };
    }

    r2Config = r2Config ?? getR2Config();
    const r2Url =
      `${r2Config.endpoint}/${r2Config.bucketName}/${audioR2ObjectKey}`;
    const response = await r2Config.s3Client.fetch(r2Url);
    if (!response.ok) {
      logStructuredError(options.r2FetchFailedEvent, {
        user_id: options.userId,
        audio_r2_key: audioR2ObjectKey,
        status: response.status,
      });
      const mappedError = options.r2FetchError?.(
        response,
        audioR2ObjectKey,
      ) ?? { message: "Failed to load staged audio.", status: 502 };
      return {
        audioBuffers: [],
        errorResponse: jsonResponse(
          { error: mappedError.message },
          mappedError.status,
        ),
      };
    }

    const readResult = await readResponseArrayBufferWithinBudget(
      response,
      MEDIA_BUDGETS.maxAudioRawBytes,
      MEDIA_BUDGET_ERRORS.audioTooLarge,
    );
    if (readResult.error || !readResult.buffer) {
      return {
        audioBuffers: [],
        errorResponse: jsonResponse(
          {
            error: readResult.error?.message ??
              MEDIA_BUDGET_ERRORS.audioTooLarge,
          },
          readResult.error?.status ?? 413,
        ),
      };
    }

    audioBuffers.push(readResult.buffer);
  }

  return { audioBuffers, r2Config };
}

export async function resolveImagePayloads(
  r2ObjectKeys: string[] | undefined,
  imageBase64s: string[] | undefined,
  fnStart: number,
): Promise<{ base64Payloads?: string[]; errorResponse?: Response }> {
  const base64Payloads: string[] = [];

  if (imageBase64s && imageBase64s.length > 0) {
    if (imageBase64s.length > MEDIA_BUDGETS.maxImageCount) {
      return {
        errorResponse: jsonResponse({ error: "Too many images." }, 400),
      };
    }
    const validBase64s: string[] = imageBase64s.filter(
      (s: string) => s.length > 0,
    );
    if (validBase64s.length === 0) {
      return {
        errorResponse: jsonResponse(
          { error: "Bad Request: imageBase64s contains no valid image data." },
          400,
        ),
      };
    }
    const totalB64Bytes = validBase64s.reduce(
      (sum: number, s: string) => sum + s.length,
      0,
    );
    // base64 inflates raw size ~4/3; 5 MB raw ≈ 6.7 MB encoded
    if (totalB64Bytes > MEDIA_BUDGETS.maxImageBase64Chars) {
      return {
        errorResponse: jsonResponse(
          {
            error: MEDIA_BUDGET_ERRORS.imageBase64TooLarge,
          },
          413,
        ),
      };
    }
    base64Payloads.push(...validBase64s);
  } else if (r2ObjectKeys && r2ObjectKeys.length > 0) {
    if (r2ObjectKeys.length > MEDIA_BUDGETS.maxImageCount) {
      return {
        errorResponse: jsonResponse({ error: "Too many r2ObjectKeys." }, 400),
      };
    }
    console.log(`[⏱ BENCH] base64_validated: ${Date.now() - fnStart}ms`);
    const { s3Client, bucketName, endpoint } = getR2Config();

    const r2Responses = await Promise.allSettled(
      r2ObjectKeys.map((key: string) =>
        s3Client.fetch(`${endpoint}/${bucketName}/${key}`)
      ),
    );

    // Process images serially: consume one body at a time so each ArrayBuffer is GC-eligible
    // before the next is loaded, preventing a peak spike of N × (raw + copy + base64) in heap.
    //
    // Per-image pre-check via Content-Length header: where R2 provides the header (non-chunked
    // transfers), we can reject oversized images before allocating the V8 buffer entirely.
    // Content-Length is intentionally not trusted as the ONLY guard (chunked transfers omit it),
    // so the post-allocation cumulative check below remains the authoritative enforcement.
    let totalBytes = 0;
    while (r2Responses.length > 0) {
      const result = r2Responses.shift()!;
      if (result.status === "rejected") {
        throw new Error(`Failed to execute concurrent R2 fetch request.`);
      }
      const r2Response = result.value as Response;
      if (!r2Response.ok) {
        throw new Error(
          `Failed to fetch an image from R2: ${r2Response.statusText}`,
        );
      }
      const readResult = await readResponseArrayBufferWithinBudget(
        r2Response,
        MEDIA_BUDGETS.maxImageRawBytes,
        MEDIA_BUDGET_ERRORS.singleImageTooLarge,
      );
      if (readResult.error) {
        return {
          errorResponse: jsonResponse(
            { error: readResult.error.message },
            readResult.error.status,
          ),
        };
      }
      const arrayBuffer = readResult.buffer!;
      // Post-allocation cumulative guard — authoritative check regardless of Content-Length.
      totalBytes += arrayBuffer.byteLength;
      if (totalBytes > MEDIA_BUDGETS.maxImageRawBytes) {
        return {
          errorResponse: jsonResponse(
            { error: MEDIA_BUDGET_ERRORS.combinedImagesTooLarge },
            413,
          ),
        };
      }
      base64Payloads.push(encodeBase64(new Uint8Array(arrayBuffer)));
    }
  }

  return { base64Payloads };
}
