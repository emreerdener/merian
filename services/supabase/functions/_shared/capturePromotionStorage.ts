/** Prepared capture-specific byte transfer. No installed runtime authority, signer,
 * route, publication, retirement or erasure. The durable operation owner must
 * register BOTH exact keys before this primitive may perform object I/O. */
import { captureObjectBackendDigest } from "./captureObjectRetirement.ts";
import { MEDIA_BUDGETS } from "./mediaBudgets.ts";
import { fetchWithDeadline } from "./outbound.ts";
import {
  cancelInitialStream,
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
  readInitialStream,
} from "./initialAnalysis/transport.ts";

export interface CapturePromotionBinding {
  readonly operationId: string;
  readonly ownerId: string;
  readonly scanId: string;
  readonly assetId: string;
  readonly sessionId: string;
  readonly backendSHA256: string;
  readonly sourceKey: string;
  readonly destinationKey: string;
  readonly contentType: string;
  readonly byteCount: number;
  readonly sha256: string;
}
export interface CapturePromotionStorageDependencies {
  readonly backend: { readonly endpoint: string; readonly bucketName: string };
  /** Required, fresh, bounded durable-operation read before EACH GET/PUT.
   * Must prove the complete saved binding, registered destination, current
   * owner/scan/merge/retirement fences and permitted phase. A matching input
   * object or successful HEAD is not an implementation of this contract.
   * No database lock spans I/O; permanent late-write cleanup is still required. */
  authorize(
    binding: Readonly<CapturePromotionBinding>,
    action: "read_source" | "write_destination" | "read_destination",
    signal: AbortSignal,
  ): Promise<void>;
  sign(request: Request, signal: AbortSignal): Promise<Request>;
  fetch: typeof fetch;
}
export type CapturePromotionStorageResult =
  | { outcome: "verified"; write: "acknowledged" | "precondition_failed" }
  | { outcome: "held"; write: "not_started" | "acknowledged" | "unknown" };

export type CapturePromotionVerificationResult = {
  outcome: "verified" | "held";
};
type PromotionRunResult =
  | CapturePromotionStorageResult
  | { outcome: "verified"; write: "not_started" };

const unavailable = () => new Error("capture_promotion_unavailable");
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
const digest = /^[0-9a-f]{64}$/;
export function snapshotCapturePromotionBinding(
  value: CapturePromotionBinding,
): Readonly<CapturePromotionBinding> {
  const fields = [
    "operationId",
    "ownerId",
    "scanId",
    "assetId",
    "sessionId",
    "backendSHA256",
    "sourceKey",
    "destinationKey",
    "contentType",
    "byteCount",
    "sha256",
  ];
  if (
    !value || Object.keys(value).length !== fields.length ||
    fields.some((key) => !Object.hasOwn(value, key))
  ) throw unavailable();
  const b = { ...value };
  for (
    const id of [b.operationId, b.ownerId, b.scanId, b.assetId, b.sessionId]
  ) {
    if (typeof id !== "string" || !uuid.test(id)) throw unavailable();
  }
  const limit = ["audio/wav", "audio/mp4"].includes(b.contentType)
    ? MEDIA_BUDGETS.maxAudioRawBytes
    : b.contentType === "video/mp4"
    ? MEDIA_BUDGETS.maxVideoRawBytes
    : ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"]
        .includes(b.contentType)
    ? MEDIA_BUDGETS.maxImageRawBytes
    : 0;
  if (
    !Number.isSafeInteger(b.byteCount) || b.byteCount < 1 ||
    b.byteCount > limit ||
    typeof b.sha256 !== "string" || !digest.test(b.sha256) ||
    typeof b.backendSHA256 !== "string" || !digest.test(b.backendSHA256) ||
    typeof b.sourceKey !== "string" ||
    !new RegExp(`^staging/${b.ownerId}/[A-Za-z0-9_.-]{1,255}$`).test(
      b.sourceKey,
    ) ||
    typeof b.destinationKey !== "string" ||
    !new RegExp(
      `^public_uploads/(free|pro)/${b.ownerId}/[A-Za-z0-9_.-]{1,255}$`,
    ).test(b.destinationKey)
  ) {
    throw unavailable();
  }
  return Object.freeze(b);
}
async function sha256(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return [...hash].map((v) => v.toString(16).padStart(2, "0")).join("");
}

/** Copies a privately retained, hash-verified snapshot, never a mutable staging
 * key via server-side COPY. One conditional write maximum; no retries/deletes.
 * A verified result is content evidence only, not durable completion, writer
 * quiescence, public visibility, source retirement or History authority. Even a
 * 200 reply is only an acknowledgement, not proof of conditional-create
 * semantics; those require separate backend qualification before installation. */
export async function transferVerifiedCapturePromotion(
  input: CapturePromotionBinding,
  deps: CapturePromotionStorageDependencies,
  caller: AbortSignal,
): Promise<CapturePromotionStorageResult> {
  const result = await runCapturePromotion(input, deps, caller, false);
  if (result.outcome === "verified") {
    // Destination-only verification cannot imply a write by this invocation.
    if (result.write === "not_started") {
      return { outcome: "held", write: "not_started" };
    }
    return { outcome: "verified", write: result.write };
  }
  return result;
}

/** Read-only recovery of a previously authorized destination write. Fresh
 * authorization must prove the registered exact binding and permitted phase.
 * Never reads staging, retries PUT, deletes, records completion or releases
 * ownership. A 404/mismatch/timeout stays held, including an unknown late write.
 * Historical recovery uses the separate retained-cohort authorization owner;
 * the fresh-action owner still requires all staged sources to be current. */
export async function verifyCapturePromotionDestination(
  input: CapturePromotionBinding,
  deps: CapturePromotionStorageDependencies,
  caller: AbortSignal,
): Promise<CapturePromotionVerificationResult> {
  const result = await runCapturePromotion(input, deps, caller, true);
  return { outcome: result.outcome };
}

async function runCapturePromotion(
  input: CapturePromotionBinding,
  inputDeps: CapturePromotionStorageDependencies,
  caller: AbortSignal,
  destinationOnly: boolean,
): Promise<PromotionRunResult> {
  let write: "not_started" | "acknowledged" | "unknown" = "not_started";
  try {
    const binding = snapshotCapturePromotionBinding(input);
    const deps = Object.freeze({
      backend: Object.freeze({ ...inputDeps.backend }),
      authorize: inputDeps.authorize.bind(inputDeps),
      sign: inputDeps.sign.bind(inputDeps),
      fetch: inputDeps.fetch.bind(inputDeps),
    });
    const backend = deps.backend;
    const endpoint = new URL(backend.endpoint);
    if (
      endpoint.protocol !== "https:" || endpoint.username ||
      endpoint.password ||
      endpoint.search || endpoint.hash || endpoint.pathname !== "/" ||
      backend.endpoint !== endpoint.origin ||
      !/^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/.test(backend.bucketName)
    ) throw unavailable();
    return await initialDeadline(caller, 60_000, async (signal) => {
      if (
        await initialAbortable(
          signal,
          () => captureObjectBackendDigest(backend),
        ) !== binding.backendSHA256
      ) {
        throw unavailable();
      }
      const request = async (
        action: "read_source" | "write_destination" | "read_destination",
        bytes: Uint8Array<ArrayBuffer> | null,
      ) => {
        if (destinationOnly && action !== "read_destination") {
          throw unavailable();
        }
        await initialAbortable(
          signal,
          () => deps.authorize(binding, action, signal),
        );
        checkInitialDeadline(signal);
        const method = action === "write_destination" ? "PUT" : "GET";
        const key = action === "read_source"
          ? binding.sourceKey
          : binding.destinationKey;
        const url = `${backend.endpoint}/${backend.bucketName}/${key}`;
        const headers = method === "PUT"
          ? new Headers({
            "Content-Type": binding.contentType,
            "Content-Length": String(binding.byteCount),
            "Cache-Control": "private, no-store",
            "If-None-Match": "*",
          })
          : new Headers({
            "Cache-Control": "no-cache, no-store",
            Pragma: "no-cache",
          });
        // Signing receives its own Request body. The retained source buffer is
        // never exposed, and a signer's replacement body is always discarded.
        const unsigned = new Request(url, {
          method,
          headers,
          body: bytes?.slice(),
          signal,
          redirect: "error",
        });
        let signed: Request;
        try {
          signed = await initialAbortable(
            signal,
            () => deps.sign(unsigned, signal),
            (late) => cancelInitialStream(late.body),
          );
        } finally {
          cancelInitialStream(unsigned.body);
        }
        try {
          if (
            signed.url !== url || signed.method !== method ||
            [...headers].some(([k, v]) => signed.headers.get(k) !== v) ||
            [...signed.headers.keys()].some((k) =>
              !headers.has(k) && ![
                "authorization",
                "host",
                "x-amz-date",
                "x-amz-content-sha256",
                "x-amz-security-token",
              ].includes(k)
            ) ||
            (signed.headers.has("host") &&
              signed.headers.get("host") !== endpoint.host)
          ) throw unavailable();
          checkInitialDeadline(signal);
          const outgoing = new Request(url, {
            method,
            headers: signed.headers,
            body: bytes?.slice(),
            signal,
            redirect: "error",
            cache: "no-store",
          });
          try {
            return await initialAbortable(
              signal,
              () =>
                fetchWithDeadline(outgoing, {
                  signal,
                  redirect: "error",
                  cache: "no-store",
                }, {
                  timeoutMs: 20_000,
                  fetcher: (request, init) => {
                    checkInitialDeadline(signal);
                    if (method === "PUT") write = "unknown";
                    return deps.fetch(request, init);
                  },
                }),
              (late) => cancelInitialStream(late.body),
            );
          } finally {
            cancelInitialStream(outgoing.body);
          }
        } finally {
          cancelInitialStream(signed.body);
        }
      };
      const read = async (action: "read_source" | "read_destination") => {
        const response = await request(action, null);
        if (
          response.status !== 200 ||
          response.headers.get("content-type") !== binding.contentType ||
          response.headers.get("content-length") !==
            String(binding.byteCount) ||
          response.headers.has("content-encoding")
        ) {
          cancelInitialStream(response.body);
          throw unavailable();
        }
        const bytes = await readInitialStream(
          response.body,
          binding.byteCount,
          signal,
        );
        if (
          bytes.byteLength !== binding.byteCount ||
          await initialAbortable(signal, () => sha256(bytes)) !== binding.sha256
        ) {
          throw unavailable();
        }
        checkInitialDeadline(signal);
        return bytes;
      };
      if (destinationOnly) {
        await read("read_destination");
        return { outcome: "verified", write: "not_started" };
      }
      const bytes = await read("read_source");
      const response = await request("write_destination", bytes);
      const status = response.status;
      cancelInitialStream(response.body);
      // Errors, including unknown write outcomes, preserve both objects for the
      // durable owner. Never turn existence or an uncertain response into retry.
      if (![200, 201, 204, 412].includes(status)) throw unavailable();
      write = "acknowledged";
      await read("read_destination");
      checkInitialDeadline(signal);
      return {
        outcome: "verified",
        write: status === 412 ? "precondition_failed" : "acknowledged",
      };
    });
  } catch {
    return { outcome: "held", write };
  }
}
