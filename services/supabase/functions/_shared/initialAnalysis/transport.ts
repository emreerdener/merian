import { fetchWithDeadline } from "../outbound.ts";
import { serviceRoleRequestHeaders } from "../serviceRoleAuth.ts";

export const INITIAL_ADMISSION_TIMEOUT_MS = 20_000;
export const INITIAL_ADMISSION_RESPONSE_BYTES = 8_192;
export const INITIAL_ASSET_BYTES = 131_072;
export const INITIAL_ASSET_TOTAL_BYTES = 1_048_576;

const unavailable = () => new Error("initial_analysis_transport_unavailable");
const deadlines = new WeakMap<AbortSignal, { at: number; abort: () => void }>();

/** Timers may be delayed by ready-stream microtasks or synchronous work. */
export function checkInitialDeadline(signal: AbortSignal): void {
  const deadline = deadlines.get(signal);
  if (deadline && performance.now() >= deadline.at) deadline.abort();
  signal.throwIfAborted();
}

export async function initialDeadline<T>(
  caller: AbortSignal,
  milliseconds: number,
  run: (signal: AbortSignal) => Promise<T>,
): Promise<T> {
  const deadline = new AbortController();
  const at = Math.min(
    performance.now() + milliseconds,
    deadlines.get(caller)?.at ?? Infinity,
  );
  const timer = setTimeout(
    () => deadline.abort(),
    Math.max(0, at - performance.now()),
  );
  const signal = AbortSignal.any([caller, deadline.signal]);
  deadlines.set(signal, { at, abort: () => deadline.abort() });
  try {
    return await run(signal);
  } finally {
    clearTimeout(timer);
  }
}

/** The owner regains control even when an injected dependency ignores abort.
 * Late values are discarded; they cannot authorize another operation. */
export function initialAbortable<T>(
  signal: AbortSignal,
  run: () => PromiseLike<T>,
  discard?: (value: T) => void,
): Promise<T> {
  return new Promise((resolve, reject) => {
    let settled = false;
    const fail = () => {
      if (settled) return;
      settled = true;
      signal.removeEventListener("abort", fail);
      reject(unavailable());
    };
    try {
      checkInitialDeadline(signal);
    } catch {
      return fail();
    }
    signal.addEventListener("abort", fail, { once: true });
    Promise.resolve().then(() => {
      checkInitialDeadline(signal);
      return run();
    }).then((value) => {
      try {
        checkInitialDeadline(signal);
      } catch {
        fail();
      }
      if (settled) {
        discard?.(value);
        fail();
        return;
      }
      settled = true;
      signal.removeEventListener("abort", fail);
      resolve(value);
    }, fail);
  });
}

export function cancelInitialStream(stream: ReadableStream<Uint8Array> | null) {
  try {
    void stream?.cancel().catch(() => {});
  } catch { /* Cancellation acknowledgement is never execution evidence. */ }
}

/** Bound actual streamed bytes before aggregation. A stalled cancellation
 * acknowledgement does not extend the deadline or retain the reader lock. */
export async function readInitialStream(
  stream: ReadableStream<Uint8Array> | null,
  limit: number,
  signal: AbortSignal,
): Promise<Uint8Array<ArrayBuffer>> {
  if (!stream) throw unavailable();
  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  let chunkCount = 0;
  let emptyCount = 0;
  let complete = false;
  try {
    for (;;) {
      const next = await initialAbortable(signal, () => reader.read());
      if (next.done) break;
      if (!(next.value instanceof Uint8Array)) throw unavailable();
      if (++chunkCount > 4_096) throw unavailable();
      if (next.value.byteLength === 0) {
        if (++emptyCount > 32) throw unavailable();
        continue;
      }
      emptyCount = 0;
      length += next.value.byteLength;
      if (length > limit) throw unavailable();
      chunks.push(new Uint8Array(next.value));
    }
    checkInitialDeadline(signal);
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    complete = true;
    return bytes;
  } finally {
    if (!complete) void reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

export type InitialAssetReader = (
  path: string,
  revision: string,
  signal: AbortSignal,
) => Promise<ReadableStream<Uint8Array>>;

const transports = new WeakSet<object>();
export interface InitialAdmissionTransport {
  call(
    args: Record<string, unknown>,
    signal: AbortSignal,
  ): Promise<
    { data: unknown; error: null | { code: string; message: string } }
  >;
}

export function assertInitialAdmissionTransport(
  value: InitialAdmissionTransport,
) {
  if (!transports.has(value)) throw unavailable();
}

/** Fixed service endpoint, single raw fetch, no SDK/auth/transient retry and no
 * redirect following. The injected fetch is a trusted test/host dependency and
 * must preserve the native fetch single-request contract. No live installer. */
export function createInitialAdmissionTransport(
  origin: string,
  serverApiKey: string,
  fetcher: typeof fetch = fetch,
): InitialAdmissionTransport {
  const url = new URL(origin);
  if (
    url.username || url.password || url.pathname !== "/" || url.search ||
    url.hash || !(url.protocol === "https:" ||
      (url.protocol === "http:" &&
        ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname)))
  ) throw unavailable();
  const headers = {
    ...serviceRoleRequestHeaders(serverApiKey),
    "Content-Type": "application/json",
    "Accept": "application/json",
  };
  const endpoint = new URL("/rest/v1/rpc/admit_initial_analysis", url).href;
  const transport: InitialAdmissionTransport = Object.freeze({
    async call(args: Record<string, unknown>, signal: AbortSignal) {
      if (
        Object.keys(args).sort().join() !==
          "p_assets_digest,p_canonical_input,p_ip_hash,p_owner,p_scan,p_submission_digest"
      ) throw unavailable();
      const body = JSON.stringify(args);
      if (new TextEncoder().encode(body).byteLength > 2_097_152) {
        throw unavailable();
      }
      const response = await initialAbortable(
        signal,
        () =>
          fetchWithDeadline(endpoint, {
            method: "POST",
            redirect: "error",
            cache: "no-store",
            credentials: "omit",
            headers,
            body,
            signal,
          }, { fetcher, timeoutMs: 12_000 }),
        (late) => cancelInitialStream(late.body),
      );
      const bytes = await readInitialStream(
        response.body,
        INITIAL_ADMISSION_RESPONSE_BYTES,
        signal,
      );
      const data = JSON.parse(
        new TextDecoder("utf-8", { fatal: true }).decode(bytes),
      );
      checkInitialDeadline(signal);
      if (response.status === 200) return { data, error: null };
      // Only the exact SQL error class/status pairing can reach semantic denial
      // decoding. Gateway/auth/rate-limit/redirect failures remain unknown.
      if (
        data && typeof data === "object" && typeof data.code === "string" &&
        typeof data.message === "string" &&
        ((response.status === 400 && data.code === "22023") ||
          (response.status === 404 && data.code === "P0002") ||
          (response.status === 500 && data.code === "55000"))
      ) {
        return {
          data: null,
          error: { code: data.code, message: data.message },
        };
      }
      throw unavailable();
    },
  });
  transports.add(transport);
  return transport;
}
