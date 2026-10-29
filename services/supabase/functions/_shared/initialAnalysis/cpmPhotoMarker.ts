/** Inactive permanent-marker executor. No claim acquisition, installed signer,
 * route, DELETE, upload capability, funding or capacity-release authority. */
import { fetchWithDeadline } from "../outbound.ts";
import {
  closeInitialCpmPhotoWrite,
  type CpmWriteClosureDependencies,
  type CpmWriteClosureInput,
  decodeCpmWriteClosureReceipt,
  snapshotCpmWriteClosureInput,
} from "./cpmPhotoWriteClosure.ts";
import {
  decodeHandoffSourceBackend,
  type HandoffSourceBackend,
} from "./mediaHandoffStorage.ts";
import { initialMediaUnavailable, mediaUUID } from "./mediaBinding.ts";
import {
  cancelInitialStream,
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
  initialRemainingDeadline,
  readInitialStream,
} from "./transport.ts";

export interface CpmPhotoMarkerDependencies
  extends CpmWriteClosureDependencies {
  /** Trusted host maps the saved profile to the separate eraser credential.
   * Sign only; no fetch, claim acquisition or client-visible capability. */
  signMarker(
    profile: string,
    request: Request,
    signal: AbortSignal,
  ): Promise<Request>;
}

async function putMarker(
  deps: CpmPhotoMarkerDependencies,
  input: Readonly<CpmWriteClosureInput>,
  backend: HandoffSourceBackend,
  signal: AbortSignal,
  recoverySignal: AbortSignal,
) {
  const current = () =>
    initialAbortable(signal, () => deps.bridge.requireCurrent(input, signal));
  await current();
  const url =
    `${backend.direct_endpoint}/${backend.private_bucket}/${backend.namespace}/${input.binding.scan_id}/${input.binding.object_id}`;
  const headers = new Headers({
    "Content-Type": "application/octet-stream",
    "Content-Length": "0",
    "Cache-Control": "private, no-store",
    "x-amz-meta-merian-state": "erased-v1",
  });
  const unsigned = new Request(url, {
    method: "PUT",
    headers,
    body: new Uint8Array(),
    signal,
    redirect: "error",
    cache: "no-store",
  });
  let signed: Request | undefined;
  try {
    signed = await initialAbortable(
      signal,
      () => deps.signMarker(backend.credential_profile, unsigned, signal),
      (late) => cancelInitialStream(late.body),
    );
    const signedHeaders = new Headers(signed.headers);
    const allowed = new Set([
      ...headers.keys(),
      "authorization",
      "host",
      "x-amz-date",
      "x-amz-content-sha256",
      "x-amz-security-token",
    ]);
    if (
      signed.url !== url || signed.method !== "PUT" ||
      [...headers].some(([k, v]) => signedHeaders.get(k) !== v) ||
      [...signedHeaders.keys()].some((k) => !allowed.has(k)) ||
      (signedHeaders.has("host") &&
        signedHeaders.get("host") !== new URL(url).host) ||
      [...signedHeaders].reduce((n, [k, v]) => n + k.length + v.length, 0) >
        16_384
    ) throw initialMediaUnavailable();
    // Never forward a signer-supplied body. Verify it is empty, then reconstruct
    // the exact zero-byte request from captured headers before any suspension.
    if (signed.body) await readInitialStream(signed.body, 0, signal);
    const request = new Request(url, {
      method: "PUT",
      headers: signedHeaders,
      body: new Uint8Array(),
      signal,
      redirect: "error",
      cache: "no-store",
    });
    try {
      await current();
      let dispatched = false;
      try {
        const response = await initialAbortable(signal, () => {
          dispatched = true;
          return fetchWithDeadline(
            request,
            { signal, redirect: "error", cache: "no-store" },
            { timeoutMs: 20_000, fetcher: deps.storage.fetch },
          );
        }, (late) => cancelInitialStream(late.body));
        // No status, including 200 or 412, proves the permanent marker exists.
        cancelInitialStream(response.body);
      } catch {
        // A dispatched write may finish late. Keep its uncertainty and allow
        // only exact observation/settlement in the reserved parent budget.
        checkInitialDeadline(recoverySignal);
        if (!dispatched) throw initialMediaUnavailable();
      }
    } finally {
      cancelInitialStream(request.body);
    }
  } finally {
    cancelInitialStream(signed?.body ?? null);
    cancelInitialStream(unsigned.body);
  }
}

/** Recover historical closure first. Otherwise capture one already-owned
 * original marker claim, attempt at most one unconditional same-key zero-byte
 * PUT, then reuse the existing closure coordinator with that exact snapshot.
 * Retirement must be irreversible: a late marker is safe, but a replaced claim
 * cannot settle. Hosted protocol/alternate-writer behavior remains unqualified. */
export async function eraseInitialCpmPhotoWrite(
  deps: CpmPhotoMarkerDependencies,
  attempt: string,
  caller: AbortSignal,
) {
  mediaUUID(attempt);
  return await initialDeadline(caller, 20_000, async (signal) => {
    try {
      const saved = await initialAbortable(
        signal,
        () => deps.bridge.readReceipt(attempt, "retired_marker", signal),
      );
      if (saved !== null) {
        return Object.freeze({
          outcome: "replay" as const,
          receipt: decodeCpmWriteClosureReceipt(
            saved,
            attempt,
            "retired_marker",
          ),
        });
      }
      const loadStarted = performance.now();
      const input = snapshotCpmWriteClosureInput(
        await initialAbortable(
          signal,
          () => deps.bridge.load(attempt, "retired_marker", signal),
        ),
        attempt,
        "retired_marker",
      );
      const claim = input.erasure_claim;
      if (!claim) throw initialMediaUnavailable();
      const remaining = Math.min(
        initialRemainingDeadline(signal),
        claim.expires_at_ms - Date.now(),
        claim.expires_at_ms - claim.issued_at_ms -
          (performance.now() - loadStarted),
      );
      // Preserve ten seconds for exact recovery, observation and settlement.
      // The closure coordinator independently preserves its five-second reserve.
      if (remaining <= 10_000) throw initialMediaUnavailable();
      return await initialDeadline(signal, remaining, async (leaseSignal) => {
        await initialDeadline(
          leaseSignal,
          remaining - 10_000,
          async (writeSignal) => {
            const backend = await initialAbortable(
              writeSignal,
              () =>
                decodeHandoffSourceBackend(
                  input.backend,
                  input.binding.backend_generation,
                  input.binding.backend_configuration_digest,
                ),
            );
            await putMarker(deps, input, backend, writeSignal, leaseSignal);
          },
        );
        checkInitialDeadline(leaseSignal);
        return await closeInitialCpmPhotoWrite(
          {
            storage: deps.storage,
            bridge: {
              readReceipt: (id, outcome, s) =>
                deps.bridge.readReceipt(id, outcome, s),
              load: () => Promise.resolve(input),
              requireCurrent: (_input, s) =>
                deps.bridge.requireCurrent(input, s),
              settle: (receipt, token, s) =>
                deps.bridge.settle(receipt, token, s),
            },
          },
          attempt,
          "retired_marker",
          leaseSignal,
        );
      });
    } catch {
      throw initialMediaUnavailable();
    }
  });
}
