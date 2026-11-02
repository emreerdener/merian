/** Inactive CPM storage observation. No issuance, SQL settlement or release
 * authority. Durable closure must separately consume this exact observation
 * under fresh registry/attempt locks and a qualified storage policy. */
import { createHash } from "node:crypto";
import { fetchWithDeadline } from "../outbound.ts";
import {
  initialMediaUnavailable,
  mediaDigest,
  mediaRecord,
  mediaTime,
  mediaUUID,
} from "./mediaBinding.ts";
import { decodeHandoffSourceBackend } from "./mediaHandoffStorage.ts";
import {
  cancelInitialStream,
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
} from "./transport.ts";

export interface CpmWriteObservationBinding {
  attempt_id: string;
  scan_id: string;
  object_id: string;
  assignment_digest: string;
  backend_generation: string;
  backend_configuration_digest: string;
  issued_at_ms: number;
  verification_policy_digest: string;
}
// Transport vocabulary only. SQL still checks the exact immutable profile's
// original_content_types; this list grants no profile or upload authority.
export const CPM_PHOTO_CONTENT_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
] as const;
export type CpmPhotoContentType = typeof CPM_PHOTO_CONTENT_TYPES[number];

export type CpmWriteObservationTarget =
  | {
    outcome: "live_object";
    role: "source" | "ai" | "display";
    byte_count: number;
    sha256: string;
    content_type: CpmPhotoContentType;
  }
  | { outcome: "retired_marker" };
export interface CpmWriteObservationDependencies {
  /** Trusted owner checks exact original facts, including live/retired state.
   * For a marker it must also check the current erasure claim. No lock spans I/O.
   * This callback is not a durable settlement or a lease against retirement. */
  requireCurrent(
    binding: Readonly<CpmWriteObservationBinding>,
    target: Readonly<CpmWriteObservationTarget>,
    signal: AbortSignal,
  ): Promise<void>;
  sign(
    profile: string,
    request: Request,
    signal: AbortSignal,
  ): Promise<Request>;
  fetch: typeof fetch;
}

export function snapshotCpmWriteObservationBinding(value: unknown) {
  const b = {
    ...mediaRecord(value, [
      "attempt_id",
      "scan_id",
      "object_id",
      "assignment_digest",
      "backend_generation",
      "backend_configuration_digest",
      "issued_at_ms",
      "verification_policy_digest",
    ]),
  };
  for (
    const k of ["attempt_id", "scan_id", "object_id", "backend_generation"]
  ) {
    mediaUUID(b[k]);
  }
  for (
    const k of [
      "assignment_digest",
      "backend_configuration_digest",
      "verification_policy_digest",
    ]
  ) {
    mediaDigest(b[k]);
  }
  mediaTime(b.issued_at_ms);
  return Object.freeze(b) as unknown as Readonly<CpmWriteObservationBinding>;
}
export function snapshotCpmWriteObservationTarget(value: unknown) {
  const t = {
    ...mediaRecord(
      value,
      value && typeof value === "object" && "outcome" in value &&
        value.outcome === "retired_marker"
        ? ["outcome"]
        : ["outcome", "role", "byte_count", "sha256", "content_type"],
    ),
  };
  if (t.outcome === "retired_marker") {
    return Object.freeze(t) as Readonly<CpmWriteObservationTarget>;
  }
  const limit = t.role === "source"
    ? 33_554_432
    : t.role === "ai"
    ? 5_242_880
    : t.role === "display"
    ? 4_194_304
    : 0;
  if (
    t.outcome !== "live_object" || !Number.isSafeInteger(t.byte_count) ||
    typeof t.byte_count !== "number" || t.byte_count < 1 ||
    t.byte_count > limit ||
    !(t.role === "source"
      ? CPM_PHOTO_CONTENT_TYPES.some((type) => type === t.content_type)
      : t.content_type === "image/jpeg")
  ) throw initialMediaUnavailable();
  mediaDigest(t.sha256);
  return Object.freeze(t) as unknown as Readonly<CpmWriteObservationTarget>;
}

/** Same bounded reader policy as readInitialStream, without retaining chunks
 * or allocating an aggregate media buffer. update consumes each view before the
 * next read; storage may reuse its backing buffer. This is byte observation,
 * not structural validation or proof of physical read/cancellation settlement. */
async function observeBytes(
  stream: ReadableStream<Uint8Array> | null,
  size: number,
  expectedHash: string | null,
  signal: AbortSignal,
): Promise<void> {
  if (!stream) throw initialMediaUnavailable();
  const reader = stream.getReader();
  let hash: ReturnType<typeof createHash> | undefined;
  let bytes = 0, chunks = 0, empty = 0;
  let complete = false;
  try {
    hash = createHash("sha256");
    for (;;) {
      const next = await initialAbortable(signal, () => reader.read());
      if (next.done) break;
      if (!(next.value instanceof Uint8Array) || ++chunks > 4096) {
        throw initialMediaUnavailable();
      }
      if (next.value.byteLength === 0) {
        if (++empty > 32) throw initialMediaUnavailable();
        continue;
      }
      empty = 0;
      if (next.value.byteLength > size - bytes) {
        throw initialMediaUnavailable();
      }
      hash.update(next.value);
      bytes += next.value.byteLength;
      checkInitialDeadline(signal);
    }
    checkInitialDeadline(signal);
    const digest = hash.digest("hex");
    if (bytes !== size || (expectedHash !== null && digest !== expectedHash)) {
      throw initialMediaUnavailable();
    }
    checkInitialDeadline(signal);
    complete = true;
  } finally {
    hash?.destroy();
    if (!complete) void reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

/** At most one direct uncached GET, no PUT/retry/HEAD fallback. All caller facts
 * are copied before the first await; no bytes, URL or credential escapes. The
 * bounded reader hashes incrementally and cancels on failure. Whole-worker
 * memory and positive physical cleanup still require qualification before install. */
export async function observeInitialCpmPhotoWrite(
  deps: CpmWriteObservationDependencies,
  value: CpmWriteObservationBinding,
  expected: CpmWriteObservationTarget,
  backendValue: unknown,
  caller: AbortSignal,
): Promise<
  Readonly<{
    binding: Readonly<CpmWriteObservationBinding>;
    target: Readonly<CpmWriteObservationTarget>;
  }>
> {
  const binding = snapshotCpmWriteObservationBinding(value),
    target = snapshotCpmWriteObservationTarget(expected);
  const backendSnapshot = {
    ...mediaRecord(backendValue, [
      "generation",
      "configuration_digest",
      "provider",
      "direct_endpoint",
      "private_bucket",
      "namespace",
      "credential_profile",
      "storage_protocol",
    ]),
  };
  return await initialDeadline(caller, 20_000, async (signal) => {
    const backend = await initialAbortable(
      signal,
      () =>
        decodeHandoffSourceBackend(
          backendSnapshot,
          binding.backend_generation,
          binding.backend_configuration_digest,
        ),
    );
    const current = () =>
      initialAbortable(
        signal,
        () => deps.requireCurrent(binding, target, signal),
      );
    await current();
    const url =
      `${backend.direct_endpoint}/${backend.private_bucket}/${backend.namespace}/${binding.scan_id}/${binding.object_id}`;
    const headers = new Headers({
      "Cache-Control": "no-cache, no-store",
      Pragma: "no-cache",
    });
    const unsigned = new Request(url, {
      method: "GET",
      headers,
      signal,
      redirect: "error",
      cache: "no-store",
    });
    const signed = await initialAbortable(
      signal,
      () => deps.sign(backend.credential_profile, unsigned, signal),
      (late) => cancelInitialStream(late.body),
    );
    try {
      const signedHeaders = new Headers(signed.headers);
      if (
        signed.url !== url || signed.method !== "GET" || signed.body !== null ||
        [...headers].some(([k, v]) => signedHeaders.get(k) !== v) ||
        [...signedHeaders.keys()].some((k) =>
          k === "range" || k === "content-encoding" || k.startsWith("if-") ||
          k.startsWith("x-amz-meta-")
        )
      ) throw initialMediaUnavailable();
      await current();
      const response = await initialAbortable(signal, () =>
        fetchWithDeadline(
          new Request(url, {
            method: "GET",
            headers: signedHeaders,
            signal,
            redirect: "error",
            cache: "no-store",
          }),
          { signal, redirect: "error", cache: "no-store" },
          { timeoutMs: 20_000, fetcher: deps.fetch },
        ), (late) => cancelInitialStream(late.body));
      const marker = target.outcome === "retired_marker";
      const size = marker ? 0 : target.byte_count;
      const type = marker ? "application/octet-stream" : target.content_type;
      const metadata = [...response.headers.keys()].filter((k) =>
        k.startsWith("x-amz-meta-")
      );
      try {
        if (
          response.status !== 200 ||
          response.headers.get("content-length") !== String(size) ||
          response.headers.get("content-type") !== type ||
          response.headers.get("cache-control") !== "private, no-store" ||
          response.headers.has("content-encoding") ||
          response.headers.has("content-range") ||
          (marker
            ? metadata.length !== 1 ||
              metadata[0] !== "x-amz-meta-merian-state" ||
              response.headers.get(metadata[0]) !== "erased-v1"
            : metadata.length !== 0)
        ) throw initialMediaUnavailable();
        if (!marker || response.body !== null) {
          await observeBytes(
            response.body,
            size,
            marker ? null : target.sha256,
            signal,
          );
        }
        await current();
        checkInitialDeadline(signal);
        return Object.freeze({ binding, target });
      } finally {
        cancelInitialStream(response.body);
      }
    } finally {
      cancelInitialStream(signed.body);
    }
  });
}
