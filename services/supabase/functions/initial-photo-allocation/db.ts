import { fetchWithDeadline } from "../_shared/outbound.ts";
import {
  requireServerApiKeyFromEnvironment,
  serviceRoleRequestHeaders,
} from "../_shared/serviceRoleAuth.ts";
import {
  checkInitialDeadline,
  initialDeadline,
  readInitialStream,
} from "../_shared/initialAnalysis/transport.ts";
import { ALLOCATION_BODY_LIMIT, type AllocationRequest } from "./contract.ts";

/** Fixed service-only RPC adapter; no SDK retry, redirect, renewal or fallback. */
export function allocationRepository(fetcher: typeof fetch = fetch) {
  const base = new URL(Deno.env.get("SUPABASE_URL") ?? "");
  if (
    base.username || base.password || base.pathname !== "/" || base.search ||
    base.hash ||
    !(base.protocol === "https:" ||
      (base.protocol === "http:" &&
        ["localhost", "127.0.0.1", "[::1]"].includes(base.hostname)))
  ) throw new Error("initial_photo_allocation_unavailable");
  const headers = {
    ...serviceRoleRequestHeaders(requireServerApiKeyFromEnvironment()),
    "Content-Type": "application/json",
    Accept: "application/json",
  };
  return Object.freeze({
    async call(
      owner: string,
      request: AllocationRequest,
      signal: AbortSignal,
    ): Promise<unknown> {
      const operation = request.version === 3
        ? (request.action === "create"
          ? "create_initial_cpm_photo_v3_allocation"
          : "get_initial_cpm_photo_v3_status")
        : (request.action === "create"
          ? "create_initial_preparation_intent"
          : "get_initial_preparation_status");
      const args = {
        p_owner: owner,
        p_scan: request.scanID,
        ...(request.action === "create"
          ? { p_candidate: request.candidateCanonical }
          : {}),
      };
      const body = JSON.stringify(args);
      if (new TextEncoder().encode(body).length > ALLOCATION_BODY_LIMIT) {
        throw new Error("initial_photo_allocation_unavailable");
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
        checkInitialDeadline(phase);
        const value = JSON.parse(
          new TextDecoder("utf-8", { fatal: true }).decode(bytes),
        );
        // Missing, foreign and deleted owners are deliberately indistinguishable.
        // A hold is not acknowledgement that the candidate ever existed.
        if (response.status === 404 && value?.code === "P0002") {
          return {
            version: 1,
            variant: "client_prepared_photo",
            outcome: "terminal_held",
            authority: "none",
            scan_id: request.scanID,
            reason: "not_found",
          };
        }
        if (response.status !== 200) {
          throw new Error("initial_photo_allocation_unavailable");
        }
        return value;
      });
    },
  });
}
