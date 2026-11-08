import { exactObject, historyUUID, invalidHistory } from "./contract.ts";

/** Informational private resolver contract: no route, reservation or execution authority. */
export const SOURCE_DISCOVERY_MAX_BYTES = 2_048;

export interface SourceDiscoveryRequest {
  readonly schema_version: 1;
  readonly observation_id: string;
  readonly source_analysis_id: string;
}

interface SourceDiscoveryScope extends SourceDiscoveryRequest {
  readonly owner_id: string;
}

export type SourceDiscoveryPhase =
  | "reserved"
  | "admitted"
  | "dispatched"
  | "draft";

export type SourceDiscoveryHoldReason =
  | "ambiguous_occupancy"
  | "malformed_linkage"
  | "coverage_incomplete"
  | "terminal_unproven";

/** Every variant is informational. Even absence/history is not admission proof. */
export type SourceDiscovery =
  & SourceDiscoveryScope
  & (
    | { readonly state: "advisory_absence" }
    | { readonly state: "history_only" }
    | {
      readonly state: "existing";
      readonly analysis_id: string;
      readonly request_digest: string;
      readonly phase: SourceDiscoveryPhase;
    }
    | {
      readonly state: "held";
      readonly reason: SourceDiscoveryHoldReason;
    }
    | { readonly state: "unavailable" }
  );

const REQUEST_KEYS = [
  "schema_version",
  "observation_id",
  "source_analysis_id",
] as const;
const RESPONSE_KEYS = [...REQUEST_KEYS, "owner_id", "state"] as const;

export function parseSourceDiscoveryRequest(
  value: unknown,
): SourceDiscoveryRequest {
  const row = exactObject(value, REQUEST_KEYS);
  if (row.schema_version !== 1) return invalidHistory();
  const observation = historyUUID(row.observation_id);
  const source = historyUUID(row.source_analysis_id);
  if (source === observation) return invalidHistory();
  return Object.freeze({
    schema_version: 1,
    observation_id: observation,
    source_analysis_id: source,
  });
}

/** Decodes only a bounded response for the authenticated owner's exact request. */
export function decodeSourceDiscovery(
  bytes: Uint8Array,
  expected: SourceDiscoveryRequest,
  ownerID: string,
): SourceDiscovery {
  if (bytes.byteLength > SOURCE_DISCOVERY_MAX_BYTES) return invalidHistory();
  let value: unknown;
  try {
    value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    return invalidHistory();
  }
  return parseSourceDiscovery(value, expected, ownerID);
}

/** Strict object boundary for a future bounded RPC adapter; errors never mean absence. */
export function parseSourceDiscovery(
  value: unknown,
  expected: SourceDiscoveryRequest,
  ownerID: string,
): SourceDiscovery {
  const request = parseSourceDiscoveryRequest(expected);
  const owner = historyUUID(ownerID);
  if (value === null || typeof value !== "object" || !("state" in value)) {
    return invalidHistory();
  }
  const state = value.state;
  const keys = state === "existing"
    ? [...RESPONSE_KEYS, "analysis_id", "request_digest", "phase"]
    : state === "held"
    ? [...RESPONSE_KEYS, "reason"]
    : RESPONSE_KEYS;
  const row = exactObject(value, keys);
  if (
    row.schema_version !== 1 || row.owner_id !== owner ||
    row.observation_id !== request.observation_id ||
    row.source_analysis_id !== request.source_analysis_id
  ) return invalidHistory();
  const scope = { ...request, owner_id: owner };
  switch (state) {
    case "advisory_absence":
    case "history_only":
    case "unavailable":
      return Object.freeze({ ...scope, state });
    case "existing": {
      const analysis = historyUUID(row.analysis_id);
      const phase = row.phase;
      if (
        analysis === request.observation_id ||
        analysis === request.source_analysis_id ||
        typeof row.request_digest !== "string" ||
        !/^[0-9a-f]{64}$/.test(row.request_digest) ||
        (phase !== "reserved" && phase !== "admitted" &&
          phase !== "dispatched" && phase !== "draft")
      ) return invalidHistory();
      return Object.freeze({
        ...scope,
        state,
        analysis_id: analysis,
        request_digest: row.request_digest,
        phase,
      });
    }
    case "held": {
      const reason = row.reason;
      if (
        reason !== "ambiguous_occupancy" && reason !== "malformed_linkage" &&
        reason !== "coverage_incomplete" && reason !== "terminal_unproven"
      ) return invalidHistory();
      return Object.freeze({ ...scope, state, reason });
    }
    default:
      return invalidHistory();
  }
}
