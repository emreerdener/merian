import { readByteStreamWithinLimit } from "./http.ts";

const MAXIMUM_OUTBOUND_HTTP_TIMEOUT_MS = 5 * 60 * 1000;

export class OutboundRequestTimeoutError extends Error {
  readonly timeoutMs: number;

  constructor(timeoutMs: number, cause?: unknown) {
    super(
      "Outbound HTTP request exceeded its deadline.",
      cause === undefined ? undefined : { cause },
    );
    this.name = "OutboundRequestTimeoutError";
    this.timeoutMs = timeoutMs;
  }
}

export interface DeadlineFetchOptions {
  fetcher?: typeof fetch;
  timeoutMs: number;
}

export function createDeadlineFetchTransport(
  timeoutMs: number,
  fetcher: typeof fetch = fetch,
): typeof fetch {
  return (input, init) =>
    fetchWithDeadline(input, init ?? {}, { fetcher, timeoutMs });
}

/**
 * Executes an outbound request with a hard deadline while preserving a
 * caller-provided cancellation signal. Edge wall-clock limits are a final
 * safety net, not an ownership mechanism: callers should always regain
 * control before a durable lease can expire.
 */
export async function fetchWithDeadline(
  input: RequestInfo | URL,
  init: RequestInit,
  options: DeadlineFetchOptions,
): Promise<Response> {
  if (
    !Number.isSafeInteger(options.timeoutMs) ||
    options.timeoutMs < 1 ||
    options.timeoutMs > MAXIMUM_OUTBOUND_HTTP_TIMEOUT_MS
  ) {
    throw new TypeError(
      "timeoutMs must be a positive integer no greater than five minutes.",
    );
  }

  const timeoutSignal = AbortSignal.timeout(options.timeoutMs);
  const callerSignal = init.signal ??
    (input instanceof Request ? input.signal : undefined);
  const signal = callerSignal
    ? AbortSignal.any([callerSignal, timeoutSignal])
    : timeoutSignal;

  try {
    return await (options.fetcher ?? fetch)(input, {
      ...init,
      signal,
    });
  } catch (error) {
    if (timeoutSignal.aborted && !callerSignal?.aborted) {
      throw new OutboundRequestTimeoutError(options.timeoutMs, error);
    }
    throw error;
  }
}

/**
 * Consumes an upstream text response within an explicit byte ceiling.
 * Decoding is strict so malformed upstream bytes cannot be silently rewritten
 * before logging or JSON parsing.
 */
export async function readResponseTextWithinLimit(
  response: Response,
  maximumBytes: number,
): Promise<string> {
  if (!Number.isSafeInteger(maximumBytes) || maximumBytes < 1) {
    throw new TypeError("maximumBytes must be a positive safe integer.");
  }

  const declaredLength = response.headers.get("content-length");
  if (
    declaredLength !== null &&
    /^(0|[1-9][0-9]*)$/.test(declaredLength.trim()) &&
    Number(declaredLength) > maximumBytes
  ) {
    try {
      await response.body?.cancel("response body exceeded limit");
    } catch {
      // The provider declaration is authoritative for early rejection even
      // when cancellation races a disconnect.
    }
    throw new RangeError("Response body exceeded its byte limit.");
  }

  const result = await readByteStreamWithinLimit(
    response.body,
    maximumBytes,
    "response body exceeded limit",
  );
  if (result.exceeded || !result.bytes) {
    throw new RangeError("Response body exceeded its byte limit.");
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(result.bytes);
}

/**
 * Parses an upstream JSON response only after applying the same streaming byte
 * ceiling and strict UTF-8 decoding used for diagnostic text.
 */
export async function readResponseJsonWithinLimit<T = unknown>(
  response: Response,
  maximumBytes: number,
): Promise<T> {
  const text = await readResponseTextWithinLimit(response, maximumBytes);
  return JSON.parse(text) as T;
}
