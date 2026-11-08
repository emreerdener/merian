/** In-progress S0 composition; no HTTP route installs this owner. SQL must
 * validate the complete original witness before emitting the fresh reply.
 * The caller must supply execution prepared from the exact verified original
 * buffers and evidence. This transport does not verify media or grant itself. */
import type { SupabaseClient } from "@supabase/supabase-js";
import type { AIQuotaReservation } from "../aiQuota.ts";
import type { PreparedAIExecution } from "../ai/contracts.ts";
import {
  type IdentificationAccountingPort,
  identificationUsageFacts,
  prepareAccountedIdentification,
} from "../ai/identificationUsage.ts";
import { fetchWithDeadline } from "../outbound.ts";
import { serviceRoleRequestHeaders } from "../serviceRoleAuth.ts";
import {
  initialCanonicalText,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { mediaDigest, mediaRecord, mediaUUID } from "./mediaBinding.ts";
import {
  cancelInitialStream,
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
  readInitialStream,
} from "./transport.ts";

export interface InitialDispatchBinding {
  readonly owner_id: string;
  readonly scan_id: string;
  readonly submission_digest: string;
  readonly config_digest: string;
  readonly funding_binding_id: string;
  readonly funding_binding_digest: string;
  readonly admission_receipt_id: string;
  readonly admission_receipt_digest: string;
}
const unavailable = () => new Error("initial_analysis_dispatch_unavailable");
const bytes = new TextEncoder();

function snapshot(
  value: InitialDispatchBinding,
): Readonly<InitialDispatchBinding> {
  const r = mediaRecord(
    parseInitialCanonicalText(initialCanonicalText(value)),
    [
      "owner_id",
      "scan_id",
      "submission_digest",
      "config_digest",
      "funding_binding_id",
      "funding_binding_digest",
      "admission_receipt_id",
      "admission_receipt_digest",
    ],
  );
  return Object.freeze({
    owner_id: mediaUUID(r.owner_id),
    scan_id: mediaUUID(r.scan_id),
    submission_digest: mediaDigest(r.submission_digest),
    config_digest: mediaDigest(r.config_digest),
    funding_binding_id: mediaUUID(r.funding_binding_id),
    funding_binding_digest: mediaDigest(r.funding_binding_digest),
    admission_receipt_id: mediaUUID(r.admission_receipt_id),
    admission_receipt_digest: mediaDigest(r.admission_receipt_digest),
  });
}

/** Private wire decoder, shared with the future fixed SQL producer contract.
 * Recovery/status documents are deliberately not accepted as fresh replies. */
function dispatchReply(value: unknown, binding: InitialDispatchBinding) {
  const r = mediaRecord(value, [
    "version",
    "owner_id",
    "scan_id",
    "submission_digest",
    "admission_receipt_id",
    "admission_receipt_digest",
    "outcome",
    "invocation_id",
  ]);
  if (
    r.version !== 1 || r.owner_id !== binding.owner_id ||
    r.scan_id !== binding.scan_id ||
    r.submission_digest !== binding.submission_digest ||
    r.admission_receipt_id !== binding.admission_receipt_id ||
    r.admission_receipt_digest !== binding.admission_receipt_digest
  ) throw unavailable();
  if (r.outcome === "held" && r.invocation_id === null) {
    return { kind: "held" } as const;
  }
  if (r.outcome !== "fresh") throw unavailable();
  return { kind: "fresh", invocationId: mediaUUID(r.invocation_id) } as const;
}

/** One dispatch attempt, one provider invocation; no fail/refund/commit lease
 * escapes to the initial caller. Lost replies and cancellation cannot retry.
 * This is an integration draft, not installed initial execution authority. */
export function prepareInitialAccountedIdentification(input: {
  client: SupabaseClient;
  reservation: AIQuotaReservation;
  execution: PreparedAIExecution;
  binding: InitialDispatchBinding;
  executionEvidence: string;
  origin: string;
  serverApiKey: string;
  caller: AbortSignal;
  fetcher?: typeof fetch;
}) {
  const binding = snapshot(input.binding);
  const leaseToken = mediaUUID(input.reservation.leaseToken);
  const evidence = input.executionEvidence;
  if (typeof evidence !== "string" || bytes.encode(evidence).length > 65_536) {
    throw unavailable();
  }
  // Structural/canonical bounds only. The fixed SQL operation and upstream
  // verifier must correlate the full original execution evidence, not its hash.
  const evidenceValue = parseInitialCanonicalText(evidence);
  if (
    !evidenceValue || typeof evidenceValue !== "object" ||
    Array.isArray(evidenceValue)
  ) {
    throw unavailable();
  }
  const expected = initialCanonicalText({
    version: 1,
    submission_digest: binding.submission_digest,
    config_digest: binding.config_digest,
    funding_binding_id: binding.funding_binding_id,
    funding_binding_digest: binding.funding_binding_digest,
    admission_receipt_id: binding.admission_receipt_id,
    admission_receipt_digest: binding.admission_receipt_digest,
  });
  if (bytes.encode(expected).length > 2048) throw unavailable();
  const base = new URL(input.origin);
  if (
    base.username || base.password || base.pathname !== "/" || base.search ||
    base.hash || !(base.protocol === "https:" ||
      (base.protocol === "http:" &&
        ["localhost", "127.0.0.1", "[::1]"].includes(base.hostname)))
  ) throw unavailable();
  const headers = Object.freeze({
    ...serviceRoleRequestHeaders(input.serverApiKey),
    "Content-Type": "application/json",
    "Accept": "application/json",
  });
  const fetcher = input.fetcher ?? fetch;
  const caller = input.caller;
  async function call(
    operation:
      | "authorize_initial_analysis_dispatch"
      | "report_initial_analysis_usage",
    args: Record<string, unknown>,
    parent: AbortSignal,
  ): Promise<unknown> {
    return await initialDeadline(parent, 5000, async (signal) => {
      const body = JSON.stringify(args);
      if (bytes.encode(body).length > 2 * (65_536 + 2048) + 4096) {
        throw unavailable();
      }
      const response = await initialAbortable(signal, () =>
        fetchWithDeadline(
          new URL(`/rest/v1/rpc/${operation}`, base),
          {
            method: "POST",
            headers,
            body,
            signal,
            redirect: "error",
            cache: "no-store",
            credentials: "omit",
          },
          { fetcher, timeoutMs: 5000 },
        ), (late) => cancelInitialStream(late.body));
      const bodyBytes = await readInitialStream(response.body, 8192, signal);
      if (response.status !== 200) throw unavailable();
      const value: unknown = JSON.parse(
        new TextDecoder("utf-8", { fatal: true }).decode(bodyBytes),
      );
      checkInitialDeadline(signal);
      return value;
    });
  }
  let dispatchAttempted = false;
  let originalInvocation: string | null = null;
  const port = Object.freeze<IdentificationAccountingPort>({
    async commit() {
      if (dispatchAttempted) return { kind: "held" } as const;
      dispatchAttempted = true;
      const value = await call("authorize_initial_analysis_dispatch", {
        p_owner: binding.owner_id,
        p_scan: binding.scan_id,
        p_expected: expected,
        p_execution_evidence: evidence,
        p_lease_token: leaseToken,
      }, caller);
      const decision = dispatchReply(value, binding);
      if (decision.kind === "fresh") originalInvocation = decision.invocationId;
      return decision;
    },
    async report(invocationId, result) {
      if (invocationId !== originalInvocation || originalInvocation === null) {
        throw unavailable();
      }
      const usage = result
        ? initialCanonicalText(identificationUsageFacts(result))
        : "{}";
      if (bytes.encode(usage).length > 2048) throw unavailable();
      // Foreground cancellation after dispatch does not cancel required usage
      // reporting. Its own five-second deadline still bounds abandoned work.
      const value = await call("report_initial_analysis_usage", {
        p_owner: binding.owner_id,
        p_scan: binding.scan_id,
        p_submission_digest: binding.submission_digest,
        p_invocation: invocationId,
        p_lease_token: leaseToken,
        p_outcome: result?.kind ?? "unknown_execution",
        p_usage: usage,
      }, new AbortController().signal);
      const r = mediaRecord(value, [
        "version",
        "owner_id",
        "scan_id",
        "submission_digest",
        "invocation_id",
        "event_id",
      ]);
      if (
        r.version !== 1 || r.owner_id !== binding.owner_id ||
        r.scan_id !== binding.scan_id ||
        r.submission_digest !== binding.submission_digest ||
        r.invocation_id !== invocationId
      ) throw unavailable();
      mediaUUID(r.event_id);
    },
  });
  const accounted = prepareAccountedIdentification(
    input.client,
    binding.owner_id,
    input.reservation,
    input.execution,
    port,
  );
  let started = false;
  return Object.freeze({
    async invoke() {
      if (started) throw unavailable();
      started = true;
      await accounted.lease.commit();
      const outcome = await accounted.invoke();
      if (originalInvocation === null) throw unavailable();
      // The durable result writer needs the original invocation association.
      // Returning its identity does not expose a second invocation capability.
      return Object.freeze({ invocationId: originalInvocation, outcome });
    },
  });
}
