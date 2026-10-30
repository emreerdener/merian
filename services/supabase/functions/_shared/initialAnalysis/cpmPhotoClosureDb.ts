/** Dormant service-only bridge. No route imports or signer installation.
 * Credentials and destination come together from server configuration. */
import {
  type CpmPhotoIssuanceBridge,
  snapshotCpmPhotoIssuanceIdentity,
} from "./cpmPhotoUploadIssuer.ts";
import { fetchWithDeadline } from "../outbound.ts";
import {
  type CpmPhotoStatusBridge,
  decodeCpmPhotoWriteStatus,
  snapshotCpmPhotoStatusIdentity,
} from "./cpmPhotoWriteStatus.ts";
import {
  requireServerApiKeyFromEnvironment,
  serviceRoleRequestHeaders,
} from "../serviceRoleAuth.ts";
import {
  type CpmWriteClosureBridge,
  type CpmWriteClosureInput,
  decodeCpmWriteClosureReceipt,
  snapshotCpmWriteClosureInput,
} from "./cpmPhotoWriteClosure.ts";
import { initialCanonicalText } from "./canonical.ts";
import { decodeHandoffSourceBackend } from "./mediaHandoffStorage.ts";
import {
  initialMediaHash,
  initialMediaUnavailable,
  mediaUUID,
} from "./mediaBinding.ts";
import {
  cancelInitialStream,
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
  readInitialStream,
} from "./transport.ts";

type Outcome = CpmWriteClosureInput["target"]["outcome"];
type Operation =
  | "read_initial_cpm_photo_write_status"
  | "begin_initial_cpm_photo_write"
  | "read_initial_cpm_photo_write_closure"
  | "read_initial_cpm_photo_observation"
  | "settle_initial_cpm_photo_write_closure";

/** The caller already owns originalClaim; this adapter never discovers or
 * acquires one. Null supports live work and historical marker receipt recovery.
 * Fresh marker work requires the exact original token supplied here. */
export function createCpmPhotoClosureDb(
  originalClaim: string | null,
  fetcher: typeof fetch = fetch,
): CpmWriteClosureBridge & CpmPhotoIssuanceBridge & CpmPhotoStatusBridge {
  if (originalClaim !== null) mediaUUID(originalClaim);
  const base = new URL(Deno.env.get("SUPABASE_URL") ?? "");
  if (
    base.username || base.password || base.pathname !== "/" || base.search ||
    base.hash ||
    !(base.protocol === "https:" || (base.protocol === "http:" &&
      ["localhost", "127.0.0.1", "[::1]"].includes(base.hostname)))
  ) throw initialMediaUnavailable();
  const headers = {
    ...serviceRoleRequestHeaders(requireServerApiKeyFromEnvironment()),
    "Content-Type": "application/json",
    "Accept": "application/json",
  };
  const claimFor = (outcome: Outcome) => {
    if (outcome === "retired_marker" && originalClaim !== null) {
      return originalClaim;
    }
    if (outcome === "live_object") return null;
    throw initialMediaUnavailable();
  };
  async function call(
    operation: Operation,
    args: Record<string, unknown>,
    signal: AbortSignal,
  ) {
    const body = JSON.stringify(args);
    if (new TextEncoder().encode(body).length > 16_384) {
      throw initialMediaUnavailable();
    }
    return await initialDeadline(signal, 5_000, async (phase) => {
      try {
        const response = await initialAbortable(phase, () =>
          fetchWithDeadline(
            new URL(`/rest/v1/rpc/${operation}`, base),
            {
              method: "POST",
              headers,
              body,
              signal: phase,
              redirect: "error",
              cache: "no-store",
              credentials: "omit",
            },
            { fetcher, timeoutMs: 5_000 },
          ), (late) => cancelInitialStream(late.body));
        const bytes = await readInitialStream(response.body, 8_192, phase);
        if (response.status !== 200) throw initialMediaUnavailable();
        const value: unknown = JSON.parse(
          new TextDecoder("utf-8", { fatal: true }).decode(bytes),
        );
        checkInitialDeadline(phase);
        return value;
      } catch {
        throw initialMediaUnavailable();
      }
    });
  }
  async function decode(
    value: unknown,
    attempt: string,
    outcome: Outcome,
    signal: AbortSignal,
  ) {
    const input = snapshotCpmWriteClosureInput(value, attempt, outcome);
    if ((input.erasure_claim?.token ?? null) !== claimFor(outcome)) {
      throw initialMediaUnavailable();
    }
    await initialAbortable(signal, () =>
      decodeHandoffSourceBackend(
        input.backend,
        input.binding.backend_generation,
        input.binding.backend_configuration_digest,
      ));
    checkInitialDeadline(signal);
    return input;
  }
  return Object.freeze(
    {
      async readStatus(identity, saved, signal) {
        if (originalClaim !== null) throw initialMediaUnavailable();
        const i = snapshotCpmPhotoStatusIdentity(identity);
        const previous = saved === null
          ? null
          : decodeCpmPhotoWriteStatus(saved, i);
        const value = await call("read_initial_cpm_photo_write_status", {
          p_owner: i.owner,
          p_scan: i.scan,
          p_digest: i.assignment_digest,
          p_object: i.object,
        }, signal);
        return decodeCpmPhotoWriteStatus(value, i, previous);
      },
      async begin(identity, signal) {
        if (originalClaim !== null) throw initialMediaUnavailable();
        const i = snapshotCpmPhotoIssuanceIdentity(identity);
        return await call("begin_initial_cpm_photo_write", {
          p_owner: i.owner,
          p_scan: i.scan,
          p_digest: i.assignment_digest,
          p_object: i.object,
          p_policy: i.policy,
        }, signal);
      },
      async readReceipt(attempt, outcome, signal) {
        mediaUUID(attempt);
        if (
          outcome !== "live_object" && outcome !== "retired_marker"
        ) throw initialMediaUnavailable();
        const value = await call("read_initial_cpm_photo_write_closure", {
          p_attempt: attempt,
          p_outcome: outcome,
        }, signal);
        return value === null
          ? null
          : decodeCpmWriteClosureReceipt(value, attempt, outcome);
      },
      async load(attempt, outcome, signal) {
        mediaUUID(attempt);
        const claim = claimFor(outcome);
        const value = await call("read_initial_cpm_photo_observation", {
          p_attempt: attempt,
          p_outcome: outcome,
          p_claim: claim,
          p_expected: null,
        }, signal);
        return await decode(value, attempt, outcome, signal);
      },
      async requireCurrent(input, signal) {
        const captured = await decode(
          input,
          input.binding.attempt_id,
          input.target.outcome,
          signal,
        );
        const value = await call("read_initial_cpm_photo_observation", {
          p_attempt: captured.binding.attempt_id,
          p_outcome: captured.target.outcome,
          p_claim: claimFor(captured.target.outcome),
          p_expected: captured,
        }, signal);
        const current = await decode(
          value,
          captured.binding.attempt_id,
          captured.target.outcome,
          signal,
        );
        if (
          initialCanonicalText(current) !== initialCanonicalText(captured)
        ) throw initialMediaUnavailable();
      },
      async settle(receipt, claim, signal) {
        const expected = decodeCpmWriteClosureReceipt(
          receipt,
          receipt.attempt_id,
          receipt.outcome,
        );
        if (claim !== claimFor(expected.outcome)) {
          throw initialMediaUnavailable();
        }
        const digest = claim === null
          ? null
          : await initialAbortable(signal, () =>
            initialMediaHash(
              new TextEncoder().encode(
                `merian.initial-analysis.cpm-erasure-claim.v1\n${claim}`,
              ),
            ));
        if (digest !== expected.claim_digest) throw initialMediaUnavailable();
        const value = await call("settle_initial_cpm_photo_write_closure", {
          p_attempt: expected.attempt_id,
          p_outcome: expected.outcome,
          p_policy: expected.policy_digest,
          p_observed_at: expected.observed_at,
          p_claim: claim,
        }, signal);
        const saved = decodeCpmWriteClosureReceipt(
          value,
          expected.attempt_id,
          expected.outcome,
        );
        if (
          initialCanonicalText(saved) !== initialCanonicalText(expected)
        ) throw initialMediaUnavailable();
        return saved;
      },
    } satisfies
      & CpmWriteClosureBridge
      & CpmPhotoIssuanceBridge
      & CpmPhotoStatusBridge,
  );
}
