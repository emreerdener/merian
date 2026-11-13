/** Observation only. This branch cannot repair, settle or return original results. */
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  cancelInitialStream,
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
  readInitialStream,
} from "../_shared/initialAnalysis/transport.ts";
import { fetchObservedScanState } from "./db.ts";

export const observationRequestBytes = 1024;
export const observationResponseBytes = 4096;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const invalid = () => new Error("scan_observation_unavailable");
function object(value: unknown, keys: string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw invalid();
  }
  const record = value as Record<string, unknown>;
  if (Object.keys(record).sort().join(",") !== keys.sort().join(",")) {
    throw invalid();
  }
  return record;
}

/** No top-level legacy scan_id or scans: even pre-marker servers refuse before
 * their legacy repair branch. Exact phase/owner binding also prevents IDOR. */
export function decodeScanObservation(body: unknown, owner: string): string {
  const outer = object(body, ["initial_recovery"]);
  const phase = object(outer.initial_recovery, [
    "version",
    "phase",
    "original",
  ]);
  const original = object(phase.original, ["owner_id", "scan_id"]);
  if (
    !uuid.test(owner) || phase.version !== 1 || phase.phase !== "observe" ||
    original.owner_id !== owner || typeof original.scan_id !== "string" ||
    !uuid.test(original.scan_id)
  ) throw invalid();
  return original.scan_id;
}

export async function readScanObservationHttp(
  request: Request,
  authenticatedOwnerID: string,
  client: SupabaseClient,
): Promise<Response> {
  const response = (body: string, status: number) =>
    new Response(body, {
      status,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      },
    });
  const refused = () =>
    response('{"error":"scan_observation_unavailable"}', 503);
  if (
    request.method !== "POST" ||
    request.headers.get("x-merian-initial-recovery") !== "observe-v1" ||
    request.headers.get("content-type")?.split(";", 1)[0].trim()
        .toLowerCase() !== "application/json" ||
    request.headers.has("content-encoding")
  ) {
    cancelInitialStream(request.body);
    return refused();
  }
  const declared = request.headers.get("content-length");
  const length = declared === null ? null : Number(declared);
  if (
    declared !== null && (!/^(0|[1-9][0-9]*)$/.test(declared) ||
      !Number.isSafeInteger(length) || length! > observationRequestBytes)
  ) {
    cancelInitialStream(request.body);
    return refused();
  }
  try {
    return await initialDeadline(request.signal, 5000, async (signal) => {
      const bytes = await readInitialStream(
        request.body,
        observationRequestBytes,
        signal,
      );
      checkInitialDeadline(signal);
      if (length !== null && bytes.byteLength !== length) throw invalid();
      const scan = decodeScanObservation(
        JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)),
        authenticatedOwnerID,
      );
      const state = await initialAbortable(
        signal,
        () =>
          fetchObservedScanState(scan, authenticatedOwnerID, client, signal),
      );
      checkInitialDeadline(signal);
      const body = JSON.stringify({
        version: 1,
        phase: "observe",
        owner_id: authenticatedOwnerID,
        scan_id: scan,
        row_exists: state.rowExists,
        job_status: state.jobStatus,
        original_result: "unavailable",
      });
      if (
        new TextEncoder().encode(body).byteLength > observationResponseBytes
      ) throw invalid();
      return response(body, 200);
    });
  } catch {
    cancelInitialStream(request.body);
    return refused();
  }
}
