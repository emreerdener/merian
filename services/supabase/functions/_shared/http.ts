/**
 * Standardized Cross-Origin Resource Sharing headers for browser preflight bypassing.
 */
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, idempotency-key, x-merian-constrained-network",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS, PUT, DELETE",
  "Access-Control-Expose-Headers":
    "Retry-After, Server-Timing, X-Merian-Edge-Region, X-Request-ID",
};

export const JSON_BODY_LIMITS = {
  small: 16 * 1024,
  standard: 64 * 1024,
  bulk: 1024 * 1024,
} as const;

export type JsonBodyLimitClass = keyof typeof JSON_BODY_LIMITS;

const PUBLIC_ERROR_CODE_PATTERN = /^[a-z][a-z0-9_]{1,63}$/;
const requestIds = new WeakMap<Request, string>();
const explicitPublicErrorResponses = new WeakSet<Response>();

export interface JsonBodyError {
  status: 400 | 413 | 415;
  code:
    | "invalid_content_length"
    | "invalid_json"
    | "invalid_json_object"
    | "payload_too_large"
    | "unsupported_media_type";
  message: string;
}

export interface JsonBodyOptions {
  allowEmpty?: boolean;
  limit: JsonBodyLimitClass;
  maxBytes?: number;
  requireObject?: boolean;
}

export class PublicHttpError extends Error {
  readonly status: number;
  readonly code: string;
  readonly retryAfterSeconds?: number;

  constructor(
    status: number,
    code: string,
    message: string,
    retryAfterSeconds?: number,
  ) {
    super(message);
    this.name = "PublicHttpError";
    if (
      !Number.isInteger(status) ||
      status < 400 ||
      status > 599 ||
      !PUBLIC_ERROR_CODE_PATTERN.test(code)
    ) {
      throw new TypeError("Invalid public HTTP error contract.");
    }
    this.status = status;
    this.code = code;
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

export function defaultPublicErrorCode(status: number): string {
  switch (status) {
    case 400:
      return "invalid_request";
    case 401:
      return "unauthorized";
    case 402:
      return "payment_required";
    case 403:
      return "forbidden";
    case 404:
      return "not_found";
    case 405:
      return "method_not_allowed";
    case 409:
      return "conflict";
    case 413:
      return "payload_too_large";
    case 415:
      return "unsupported_media_type";
    case 422:
      return "unprocessable_entity";
    case 429:
      return "rate_limited";
    case 502:
      return "upstream_unavailable";
    case 503:
      return "service_unavailable";
    case 504:
      return "upstream_timeout";
    default:
      return status >= 500 ? "internal_error" : "request_failed";
  }
}

export function publicHttpError(
  status: number,
  message: string,
  code = defaultPublicErrorCode(status),
  retryAfterSeconds?: number,
): PublicHttpError {
  return new PublicHttpError(status, code, message, retryAfterSeconds);
}

export function requestIdFor(req: Request): string {
  let requestId = requestIds.get(req);
  if (!requestId) {
    requestId = crypto.randomUUID();
    requestIds.set(req, requestId);
  }
  return requestId;
}

/**
 * Standardized JSON response helper.
 */
export function jsonResponse(
  payload: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(payload), {
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      ...extraHeaders,
    },
    status,
  });
}

export function publicErrorResponse(
  req: Request,
  status: number,
  code: string,
  message: string,
  options: {
    extraHeaders?: Record<string, string>;
    retryAfterSeconds?: number;
  } = {},
): Response {
  if (
    !Number.isInteger(status) ||
    status < 400 ||
    status > 599 ||
    !PUBLIC_ERROR_CODE_PATTERN.test(code) ||
    typeof message !== "string" ||
    message.trim().length < 1 ||
    message.length > 500 ||
    (options.retryAfterSeconds !== undefined &&
      (!Number.isInteger(options.retryAfterSeconds) ||
        options.retryAfterSeconds < 1 ||
        options.retryAfterSeconds > 86_400))
  ) {
    throw new TypeError("Invalid public error response contract.");
  }
  const requestId = requestIdFor(req);
  const retryAfter = options.retryAfterSeconds;
  const response = jsonResponse(
    {
      error: message,
      code,
      request_id: requestId,
      ...(retryAfter ? { retry_after_seconds: retryAfter } : {}),
    },
    status,
    {
      ...options.extraHeaders,
      "Cache-Control": "private, no-store",
      "X-Request-ID": requestId,
      ...(retryAfter ? { "Retry-After": String(retryAfter) } : {}),
    },
  );
  explicitPublicErrorResponses.add(response);
  return response;
}

export function isExplicitPublicErrorResponse(response: Response): boolean {
  return explicitPublicErrorResponses.has(response);
}

/**
 * Timing-safe string comparison to prevent timing attacks on secret validation.
 * Uses constant-time XOR comparison so execution time does not reveal partial matches.
 */
export function timingSafeCompare(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const aBytes = encoder.encode(a);
  const bBytes = encoder.encode(b);
  if (aBytes.byteLength !== bBytes.byteLength) return false;
  let result = 0;
  for (let i = 0; i < aBytes.byteLength; i++) {
    result |= aBytes[i] ^ bBytes[i];
  }
  return result === 0;
}

/**
 * Validates that all required fields are present and, for strings, non-empty in the request body.
 *
 * Returns a 400 `Response` if any field is missing or null, or if a required string field
 * is empty/whitespace-only. Boolean `false` and numeric `0` are treated as present.
 * Otherwise returns `null`
 * so the caller can proceed.
 *
 * @example
 * const err = requireParams(body, ["scan_id", "scientific_name"]);
 * if (err) return err;
 */
export function requireParams(
  body: Record<string, unknown>,
  fields: string[],
): Response | null {
  const missing = fields.filter((field) => {
    if (!(field in body)) return true;

    const value = body[field];
    if (value === null || value === undefined) return true;
    if (typeof value === "string" && value.trim().length === 0) return true;

    return false;
  });
  if (missing.length === 0) return null;
  return jsonResponse(
    {
      error: `Missing required parameter${missing.length > 1 ? "s" : ""}: ${
        missing.join(", ")
      }`,
    },
    400,
  );
}

export interface BoundedByteStreamResult {
  bytes?: Uint8Array;
  exceeded?: true;
}

/**
 * Reads a byte stream with memory proportional to its accepted bytes rather
 * than its chunk count. Network runtimes may deliver extremely small chunks;
 * retaining each chunk object separately would otherwise create an allocation
 * amplification path even when the byte ceiling is small.
 */
export async function readByteStreamWithinLimit(
  stream: ReadableStream<Uint8Array> | null,
  maximumBytes: number,
  cancelReason = "stream exceeded limit",
): Promise<BoundedByteStreamResult> {
  if (!Number.isSafeInteger(maximumBytes) || maximumBytes < 1) {
    throw new TypeError("maximumBytes must be a positive safe integer.");
  }
  if (!stream) return { bytes: new Uint8Array() };

  const reader = stream.getReader();
  let buffer = new Uint8Array();
  let totalBytes = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value || value.byteLength === 0) continue;
      if (value.byteLength > maximumBytes - totalBytes) {
        try {
          await reader.cancel(cancelReason);
        } catch {
          // The size decision is authoritative even if transport cancellation
          // races a peer disconnect.
        }
        return { exceeded: true };
      }

      const requiredBytes = totalBytes + value.byteLength;
      if (requiredBytes > buffer.byteLength) {
        let nextCapacity = buffer.byteLength === 0
          ? Math.min(maximumBytes, Math.max(1024, requiredBytes))
          : buffer.byteLength;
        while (nextCapacity < requiredBytes) {
          nextCapacity = Math.min(
            maximumBytes,
            Math.max(requiredBytes, nextCapacity * 2),
          );
        }
        const grown = new Uint8Array(nextCapacity);
        grown.set(buffer.subarray(0, totalBytes));
        buffer = grown;
      }

      buffer.set(value, totalBytes);
      totalBytes = requiredBytes;
    }
  } finally {
    reader.releaseLock();
  }

  return {
    bytes: totalBytes === buffer.byteLength
      ? buffer
      : buffer.subarray(0, totalBytes),
  };
}

/**
 * Reads a request body incrementally, rejecting an oversized declared length
 * before allocation and an oversized streamed length before buffering another
 * chunk. This is also used by signed webhook routes that must retain raw bytes.
 */
export async function readRequestBodyWithinLimit(
  req: Request,
  maximumBytes: number,
): Promise<{ bytes?: Uint8Array; error?: JsonBodyError }> {
  if (!Number.isSafeInteger(maximumBytes) || maximumBytes < 1) {
    throw new TypeError("maximumBytes must be a positive safe integer.");
  }

  const declaredLength = req.headers.get("content-length");
  let declaredBytes: number | null = null;
  if (declaredLength !== null) {
    const normalizedLength = declaredLength.trim();
    if (!/^(0|[1-9][0-9]*)$/.test(normalizedLength)) {
      return {
        error: {
          status: 400,
          code: "invalid_content_length",
          message: "Invalid Content-Length header.",
        },
      };
    }
    declaredBytes = Number(normalizedLength);
    if (!Number.isSafeInteger(declaredBytes)) {
      return {
        error: {
          status: 400,
          code: "invalid_content_length",
          message: "Invalid Content-Length header.",
        },
      };
    }
    if (declaredBytes > maximumBytes) {
      return {
        error: {
          status: 413,
          code: "payload_too_large",
          message: "Request body exceeds this endpoint's byte limit.",
        },
      };
    }
  }

  const streamResult = await readByteStreamWithinLimit(
    req.body,
    maximumBytes,
    "request body exceeded limit",
  );
  if (streamResult.exceeded || !streamResult.bytes) {
    return {
      error: {
        status: 413,
        code: "payload_too_large",
        message: "Request body exceeds this endpoint's byte limit.",
      },
    };
  }
  const bytes = streamResult.bytes;

  if (declaredBytes !== null && declaredBytes !== bytes.byteLength) {
    return {
      error: {
        status: 400,
        code: "invalid_content_length",
        message: "Content-Length does not match the request body.",
      },
    };
  }
  return { bytes };
}

export function isJsonMediaType(contentType: string | null): boolean {
  if (!contentType) return false;
  const mediaType = contentType.split(";", 1)[0].trim().toLowerCase();
  return mediaType === "application/json" ||
    /^application\/[a-z0-9!#$&^_.+-]+\+json$/.test(mediaType);
}

export async function readBoundedJsonBody<T>(
  req: Request,
  options: JsonBodyOptions,
): Promise<{ value?: T; error?: JsonBodyError }> {
  const maximumBytes = options.maxBytes ?? JSON_BODY_LIMITS[options.limit];
  const structurallyEmpty = req.body === null;
  if (!isJsonMediaType(req.headers.get("content-type"))) {
    if (options.allowEmpty === true && structurallyEmpty) {
      return { value: {} as T };
    }
    return {
      error: {
        status: 415,
        code: "unsupported_media_type",
        message: "Content-Type must be application/json.",
      },
    };
  }

  const readResult = await readRequestBodyWithinLimit(req, maximumBytes);
  if (readResult.error || !readResult.bytes) {
    return { error: readResult.error };
  }
  if (readResult.bytes.byteLength === 0) {
    if (options.allowEmpty === true) return { value: {} as T };
    return {
      error: {
        status: 400,
        code: "invalid_json",
        message: "JSON body is required.",
      },
    };
  }

  let decoded: string;
  try {
    decoded = new TextDecoder("utf-8", { fatal: true }).decode(
      readResult.bytes,
    );
  } catch {
    return {
      error: {
        status: 400,
        code: "invalid_json",
        message: "JSON body must use valid UTF-8.",
      },
    };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(decoded);
  } catch {
    return {
      error: {
        status: 400,
        code: "invalid_json",
        message: "Invalid JSON body.",
      },
    };
  }

  if (
    options.requireObject !== false &&
    (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
  ) {
    return {
      error: {
        status: 400,
        code: "invalid_json_object",
        message: "JSON body must be an object.",
      },
    };
  }
  return { value: parsed as T };
}

/**
 * Parses a bounded JSON object and converts parser failures into the public
 * error envelope used by Edge Functions.
 */
export async function parseJsonBody<T = Record<string, unknown>>(
  req: Request,
  options: JsonBodyOptions,
): Promise<T | Response> {
  const result = await readBoundedJsonBody<T>(req, options);
  if (result.error || result.value === undefined) {
    const error = result.error ?? {
      status: 400,
      code: "invalid_json",
      message: "Invalid JSON body.",
    };
    return publicErrorResponse(
      req,
      error.status,
      error.code,
      error.message,
    );
  }
  return result.value;
}
