/** Inactive server coordinator. No installed bridge, route or issuer.
 * Only authoritative database facts enter observation; client proof is never an
 * argument. SQL remains the durable lifecycle and policy authority. */
import {
  type CpmWriteObservationBinding,
  type CpmWriteObservationDependencies,
  type CpmWriteObservationTarget,
  observeInitialCpmPhotoWrite,
  snapshotCpmWriteObservationBinding,
  snapshotCpmWriteObservationTarget,
} from "./cpmPhotoWriteObservation.ts";
import {
  initialMediaHash,
  initialMediaUnavailable,
  mediaDigest,
  mediaRecord,
  mediaTime,
  mediaUUID,
} from "./mediaBinding.ts";
import {
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
  initialRemainingDeadline,
} from "./transport.ts";

type Outcome = CpmWriteObservationTarget["outcome"];
export interface CpmWriteClosureReceipt {
  attempt_id: string;
  outcome: Outcome;
  policy_digest: string;
  observed_at: string;
  claim_digest: string | null;
}
export interface CpmWriteClosureInput {
  binding: CpmWriteObservationBinding;
  target: CpmWriteObservationTarget;
  backend: Record<string, unknown>;
  admission_expires_at_ms: number;
  erasure_claim:
    | { token: string; issued_at_ms: number; expires_at_ms: number }
    | null;
}
export interface CpmWriteClosureBridge {
  /** Authoritative exact (attempt, outcome) receipt only; never a cached state
   * or storage-existence guess. A historical receipt grants no fresh IO. */
  readReceipt(
    attempt: string,
    outcome: Outcome,
    signal: AbortSignal,
  ): Promise<unknown | null>;
  /** Read original issued attempt, saved declarations and immutable backend;
   * marker mode captures the already-owned ORIGINAL erasure claim, never claims
   * or renews it. No private declaration is needed in marker mode. */
  load(
    attempt: string,
    outcome: Outcome,
    signal: AbortSignal,
  ): Promise<CpmWriteClosureInput>;
  /** Recheck exact original facts and current policy/lifecycle, including the
   * same captured claim. No transaction/lock may span storage I/O. */
  requireCurrent(
    input: Readonly<CpmWriteClosureInput>,
    signal: AbortSignal,
  ): Promise<void>;
  /** Map to settle_initial_cpm_photo_write_closure with the exact original
   * token and observed time. SQL independently fences every fresh transition. */
  settle(
    receipt: Readonly<CpmWriteClosureReceipt>,
    originalClaim: string | null,
    signal: AbortSignal,
  ): Promise<unknown>;
}
export interface CpmWriteClosureDependencies {
  bridge: CpmWriteClosureBridge;
  storage: Pick<CpmWriteObservationDependencies, "sign" | "fetch">;
}
/** Exact SQL microsecond identity, separate from conservative scheduling ms.
 * Date is used only to reject impossible dates; the original string is returned. */
export function cpmClosureTimestamp(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$/.test(
      value,
    ) || value.startsWith("0000")
  ) {
    throw initialMediaUnavailable();
  }
  const milliseconds = value.slice(0, 23) + "Z";
  const parsed = Date.parse(milliseconds);
  if (
    !Number.isFinite(parsed) || new Date(parsed).toISOString() !== milliseconds
  ) {
    throw initialMediaUnavailable();
  }
  return value;
}
export function decodeCpmWriteClosureReceipt(
  value: unknown,
  attempt: string,
  outcome: Outcome,
) {
  const r = {
    ...mediaRecord(value, [
      "attempt_id",
      "outcome",
      "policy_digest",
      "observed_at",
      "claim_digest",
    ]),
  };
  if (mediaUUID(r.attempt_id) !== attempt || r.outcome !== outcome) {
    throw initialMediaUnavailable();
  }
  mediaDigest(r.policy_digest);
  cpmClosureTimestamp(r.observed_at);
  if (outcome === "retired_marker") mediaDigest(r.claim_digest);
  else if (r.claim_digest !== null) throw initialMediaUnavailable();
  return Object.freeze(r) as unknown as Readonly<CpmWriteClosureReceipt>;
}
function exact(value: unknown, expected: Readonly<CpmWriteClosureReceipt>) {
  const saved = decodeCpmWriteClosureReceipt(
    value,
    expected.attempt_id,
    expected.outcome,
  );
  if (
    saved.policy_digest !== expected.policy_digest ||
    saved.observed_at !== expected.observed_at ||
    saved.claim_digest !== expected.claim_digest
  ) throw initialMediaUnavailable();
  return saved;
}
export function snapshotCpmWriteClosureInput(
  value: unknown,
  attempt: string,
  outcome: Outcome,
): Readonly<CpmWriteClosureInput> {
  const r = mediaRecord(value, [
    "binding",
    "target",
    "backend",
    "admission_expires_at_ms",
    "erasure_claim",
  ]);
  const binding = snapshotCpmWriteObservationBinding(r.binding),
    target = snapshotCpmWriteObservationTarget(r.target);
  if (mediaUUID(binding.attempt_id) !== attempt || target.outcome !== outcome) {
    throw initialMediaUnavailable();
  }
  mediaDigest(binding.verification_policy_digest);
  mediaTime(binding.issued_at_ms);
  const admission = mediaTime(r.admission_expires_at_ms);
  if (admission <= binding.issued_at_ms) throw initialMediaUnavailable();
  const backend = Object.freeze({
    ...mediaRecord(r.backend, [
      "generation",
      "configuration_digest",
      "provider",
      "direct_endpoint",
      "private_bucket",
      "namespace",
      "credential_profile",
      "storage_protocol",
    ]),
  });
  let claim = null;
  if (outcome === "retired_marker") {
    const c = mediaRecord(r.erasure_claim, [
      "token",
      "issued_at_ms",
      "expires_at_ms",
    ]);
    claim = Object.freeze({
      token: mediaUUID(c.token),
      issued_at_ms: mediaTime(c.issued_at_ms),
      expires_at_ms: mediaTime(c.expires_at_ms),
    });
    if (
      claim.expires_at_ms <= claim.issued_at_ms ||
      claim.expires_at_ms - claim.issued_at_ms > 60_000
    ) throw initialMediaUnavailable();
  } else if (r.erasure_claim !== null) throw initialMediaUnavailable();
  return Object.freeze({
    binding,
    target,
    backend,
    admission_expires_at_ms: admission,
    erasure_claim: claim,
  });
}
/** One 20s aggregate operation, with 5s reserved after observation. Unknown
 * settlement reads only the exact receipt once; it never repeats load, claim,
 * GET or settlement. Late dependency completion cannot start another action.
 * Returned receipts are historical metadata, not new signing/release authority. */
export async function closeInitialCpmPhotoWrite(
  deps: CpmWriteClosureDependencies,
  attempt: string,
  outcome: Outcome,
  caller: AbortSignal,
): Promise<
  Readonly<
    { outcome: "settled" | "replay"; receipt: Readonly<CpmWriteClosureReceipt> }
  >
> {
  mediaUUID(attempt);
  if (outcome !== "live_object" && outcome !== "retired_marker") {
    throw initialMediaUnavailable();
  }
  const started = performance.now();
  return await initialDeadline(caller, 20_000, async (signal) => {
    try {
      const read = () =>
        initialAbortable(
          signal,
          () => deps.bridge.readReceipt(attempt, outcome, signal),
        );
      const saved = await read();
      if (saved !== null) {
        return Object.freeze({
          outcome: "replay" as const,
          receipt: decodeCpmWriteClosureReceipt(saved, attempt, outcome),
        });
      }
      const loadStarted = performance.now();
      const input = snapshotCpmWriteClosureInput(
        await initialAbortable(
          signal,
          () => deps.bridge.load(attempt, outcome, signal),
        ),
        attempt,
        outcome,
      );
      const claim = input.erasure_claim;
      const remaining = Math.min(
        initialRemainingDeadline(signal),
        20_000 - (performance.now() - started),
        claim
          ? Math.min(
            claim.expires_at_ms - Date.now(),
            claim.expires_at_ms - claim.issued_at_ms -
              (performance.now() - loadStarted),
          )
          : input.admission_expires_at_ms - Date.now(),
      );
      if (remaining <= 5_000) throw initialMediaUnavailable();
      return await initialDeadline(signal, remaining, async (leaseSignal) => {
        await initialDeadline(
          leaseSignal,
          remaining - 5_000,
          (storageSignal) =>
            observeInitialCpmPhotoWrite(
              {
                ...deps.storage,
                requireCurrent: (_binding, _target, currentSignal) =>
                  deps.bridge.requireCurrent(input, currentSignal),
              },
              input.binding,
              input.target,
              input.backend,
              storageSignal,
            ),
        );
        checkInitialDeadline(leaseSignal);
        const observed = Date.now();
        if (
          observed < input.binding.issued_at_ms ||
          (claim && observed < claim.issued_at_ms)
        ) throw initialMediaUnavailable();
        const claimDigest = claim
          ? await initialAbortable(
            leaseSignal,
            () =>
              initialMediaHash(
                new TextEncoder().encode(
                  `merian.initial-analysis.cpm-erasure-claim.v1\n${claim.token}`,
                ),
              ),
          )
          : null;
        const expected = Object.freeze({
          attempt_id: attempt,
          outcome,
          policy_digest: input.binding.verification_policy_digest,
          observed_at: new Date(observed).toISOString().replace("Z", "000Z"),
          claim_digest: claimDigest,
        });
        try {
          const answer = await initialAbortable(
            leaseSignal,
            () =>
              deps.bridge.settle(expected, claim?.token ?? null, leaseSignal),
          );
          return Object.freeze({
            outcome: "settled" as const,
            receipt: exact(answer, expected),
          });
        } catch {
          checkInitialDeadline(leaseSignal);
          const recovered = await initialAbortable(
            leaseSignal,
            () => deps.bridge.readReceipt(attempt, outcome, leaseSignal),
          );
          return Object.freeze({
            outcome: "replay" as const,
            receipt: exact(recovered, expected),
          });
        }
      });
    } catch {
      throw initialMediaUnavailable();
    }
  });
}
