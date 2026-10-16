import { fetchWithDeadline } from "../outbound.ts";
import {
  requireServerApiKeyFromEnvironment,
  serviceRoleRequestHeaders,
} from "../serviceRoleAuth.ts";
import {
  checkInitialDeadline,
  initialDeadline,
  readInitialStream,
} from "./transport.ts";
import type {
  PreparationExecutionDependencies,
  PreparationOperation,
} from "./preparationExecution.ts";

const payloadFields: Record<PreparationOperation, string | null> = {
  get_initial_preparation_execution_status: null,
  settle_initial_preparation_sources: "p_receipt",
  issue_initial_preparation_execution: "p_source_digest",
  register_initial_preparation_output: "p_manifest",
  settle_initial_preparation_outcome: "p_outcome",
};
/** Fixed dormant service transport. Never retries a grant or follows redirects.
 * The coordinator supplies phase deadlines; exact known replies survive local
 * cancellation there. Unknown network/SQL outcomes require original recovery. */
export function createPreparationExecutionTransport(
  fetcher: typeof fetch = fetch,
): Pick<PreparationExecutionDependencies, "call"> {
  // Origin and credential are captured together from trusted server configuration.
  // Neither RPC arguments nor callers can select a credential destination.
  const base = new URL(Deno.env.get("SUPABASE_URL") ?? "");
  if (
    base.username || base.password || base.pathname !== "/" || base.search ||
    base.hash ||
    !(base.protocol === "https:" ||
      (base.protocol === "http:" &&
        ["localhost", "127.0.0.1", "[::1]"].includes(base.hostname)))
  ) throw new Error("initial_analysis_transport_unavailable");
  const headers = {
    ...serviceRoleRequestHeaders(requireServerApiKeyFromEnvironment()),
    "Content-Type": "application/json",
    "Accept": "application/json",
  };
  return Object.freeze({
    async call(
      operation: PreparationOperation,
      args: Record<string, unknown>,
      signal: AbortSignal,
    ): Promise<unknown> {
      if (!Object.hasOwn(payloadFields, operation)) {
        throw new Error("initial_analysis_transport_unavailable");
      }
      const field = payloadFields[operation],
        expected = [
          "p_owner",
          "p_scan",
          "p_assignment_digest",
          ...(field === null ? [] : [field]),
        ].sort();
      if (Object.keys(args).sort().join() !== expected.join()) {
        throw new Error("initial_analysis_transport_unavailable");
      }
      const body = JSON.stringify(args);
      if (new TextEncoder().encode(body).length > 262144) {
        throw new Error("initial_analysis_transport_unavailable");
      }
      return await initialDeadline(signal, 5000, async (phase) => {
        checkInitialDeadline(phase);
        const response = await fetchWithDeadline(
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
          { fetcher, timeoutMs: 5000 },
        );
        const bytes = await readInitialStream(response.body, 524288, phase);
        if (response.status !== 200) {
          throw new Error("initial_analysis_transport_unavailable");
        }
        checkInitialDeadline(phase);
        return JSON.parse(
          new TextDecoder("utf-8", { fatal: true }).decode(bytes),
        );
      });
    },
  });
}
