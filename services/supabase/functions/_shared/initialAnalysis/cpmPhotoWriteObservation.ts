/** Inactive CPM storage observation. No issuance, SQL settlement or release
 * authority. Durable closure must separately consume this exact observation
 * under fresh registry/attempt locks and a qualified storage policy. */
import { fetchWithDeadline } from "../outbound.ts";
import {
  initialMediaHash,
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
  readInitialStream,
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
export type CpmWriteObservationTarget =
  | {
    outcome: "live_object";
    role: "source" | "ai" | "display";
    byte_count: number;
    sha256: string;
    content_type: "image/jpeg" | "image/png";
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

function snapshotBinding(value: CpmWriteObservationBinding) {
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
function snapshotTarget(value: CpmWriteObservationTarget) {
  const t = {
    ...mediaRecord(
      value,
      value?.outcome === "retired_marker"
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
    (t.content_type !== "image/jpeg" && t.content_type !== "image/png")
  ) throw initialMediaUnavailable();
  mediaDigest(t.sha256);
  return Object.freeze(t) as unknown as Readonly<CpmWriteObservationTarget>;
}

/** At most one direct uncached GET, no PUT/retry/HEAD fallback. All caller facts
 * are copied before the first await; no bytes, URL or credential escapes. The
 * existing stream owner bounds bytes/chunks and cancels on failure. Whole-buffer
 * hashing still needs CPM-specific hosted memory qualification before install. */
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
  const binding = snapshotBinding(value), target = snapshotTarget(expected);
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
        const bytes = marker && response.body === null
          ? new Uint8Array()
          : await readInitialStream(response.body, size, signal);
        if (
          bytes.length !== size ||
          (!marker &&
            await initialAbortable(signal, () => initialMediaHash(bytes)) !==
              target.sha256)
        ) throw initialMediaUnavailable();
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
