import type { SupabaseClient } from "@supabase/supabase-js";
import {
  exactObject,
  HistoryError,
  historyUUID,
  invalidHistory,
} from "../_shared/analysisHistory/contract.ts";
import {
  type InitialRetentionRequest,
  initialRetentionRequest,
} from "../_shared/analysisHistory/initialEvidenceRetention.ts";
import { recoverAcceptedInitialResult } from "../_shared/analysisHistory/initialEvidenceRecovery.ts";
import {
  finalizeInitialEvidence,
  initialEvidenceFinalizationDependencies,
} from "../_shared/analysisHistory/initialEvidenceFinalization.ts";
import { recoverPrivateCaptureCompletion } from "../_shared/analysisHistory/privateCaptureCompletion.ts";
import { initialEvidenceCompletionVerifier } from "../_shared/identify/initialEvidenceEnvelopeV1.ts";
import { isScanGeoprivacy } from "../_shared/identify/db.ts";
import {
  initialAbortable,
  initialDeadline,
} from "../_shared/initialAnalysis/transport.ts";

export interface PrivateFinalizationCandidate {
  owner: string;
  request: InitialRetentionRequest;
  telemetry: Record<string, unknown>;
}

/** This dependency surface deliberately has no inference, quota, begin, upload,
 * public-media promotion, or terminal-failure operation. */
export interface PrivateFinalizationDependencies {
  claim(signal: AbortSignal): Promise<unknown>;
  completed(
    candidate: PrivateFinalizationCandidate,
    signal: AbortSignal,
  ): Promise<unknown | null>;
  accepted(
    candidate: PrivateFinalizationCandidate,
    signal: AbortSignal,
  ): ReturnType<typeof recoverAcceptedInitialResult>;
  finalize(
    candidate: PrivateFinalizationCandidate,
    accepted: NonNullable<
      Awaited<ReturnType<typeof recoverAcceptedInitialResult>>
    >,
    signal: AbortSignal,
  ): Promise<unknown>;
}

async function candidate(
  value: unknown,
): Promise<PrivateFinalizationCandidate> {
  const row = exactObject(structuredClone(value), [
    "schema_version",
    "owner_id",
    "request",
    "telemetry",
  ]);
  const owner = historyUUID(row.owner_id),
    request = await initialRetentionRequest(row.request);
  if (
    row.schema_version !== 1 ||
    request.evidence_manifest.schema_version !== 9 ||
    !row.telemetry || typeof row.telemetry !== "object" ||
    Array.isArray(row.telemetry) ||
    !isScanGeoprivacy((row.telemetry as Record<string, unknown>).geoprivacy)
  ) return invalidHistory();
  return {
    owner,
    request,
    telemetry: row.telemetry as Record<string, unknown>,
  };
}

/** Bounded finalization-only continuation. A malformed or uncertain candidate
 * stays held until the scheduling lease expires; its accepted result is never
 * converted into another provider attempt or terminal funding settlement. */
export async function continuePrivateCaptureFinalizations(
  dependencies: PrivateFinalizationDependencies,
  caller: AbortSignal,
) {
  const signal = AbortSignal.any([caller, AbortSignal.timeout(90_000)]);
  signal.throwIfAborted();
  const rows = structuredClone(await dependencies.claim(signal));
  if (!Array.isArray(rows) || rows.length > 5) return invalidHistory();
  const summary = {
    claimed: rows.length,
    completed: 0,
    alreadyComplete: 0,
    held: 0,
  };
  for (const row of rows) {
    try {
      signal.throwIfAborted();
      const current = await candidate(row);
      const verify = initialEvidenceCompletionVerifier({
        ownerID: current.owner,
        scanID: current.request.scan_id,
        generation: current.request.generation,
        evidenceDigest: current.request.evidence_digest,
      });
      // A foreground worker may have sealed after our claim. Its exact proof
      // wins before attempting retained-media recovery or another insertion.
      const completed = await dependencies.completed(current, signal);
      signal.throwIfAborted();
      if (completed !== null) {
        verify(completed);
        summary.alreadyComplete++;
        continue;
      }
      const accepted = await dependencies.accepted(current, signal);
      signal.throwIfAborted();
      if (accepted === null) {
        summary.held++;
        continue;
      }
      const result = await dependencies.finalize(current, accepted, signal);
      signal.throwIfAborted();
      verify(result);
      summary.completed++;
    } catch {
      // No payload, account identity, accepted result or arbitrary transport
      // error is logged. The existing immutable records remain the evidence.
      summary.held++;
    }
  }
  return summary;
}

function plan(current: PrivateFinalizationCandidate) {
  return {
    schema_version: 1,
    scan_id: current.request.scan_id,
    generation: current.request.generation,
    items: current.request.evidence_manifest.items.map((item) => {
      if (item.kind === "audio") {
        return {
          kind: item.kind,
          source: item.source,
          prepared_media_id: item.prepared.media_id,
        };
      }
      if (item.kind === "video") {
        return {
          ...item,
          audio: item.audio === null ? null : {
            source: item.audio.source,
            prepared_media_id: item.audio.prepared.media_id,
          },
        };
      }
      return item;
    }),
  };
}

export function privateFinalizationDependencies(
  client: SupabaseClient,
): PrivateFinalizationDependencies {
  return {
    claim: (signal) =>
      initialDeadline(signal, 10_000, async (current) => {
        const { data, error } = await initialAbortable(current, () =>
          client.rpc("claim_private_capture_finalizations", { p_limit: 5 })
            .abortSignal(current));
        if (error) {
          throw new HistoryError("analysis_history_unavailable");
        }
        return data;
      }),
    completed: (current, signal) =>
      recoverPrivateCaptureCompletion(
        client,
        current.owner,
        plan(current),
        signal,
      ),
    accepted: (current, signal) =>
      recoverAcceptedInitialResult(
        client,
        current.owner,
        current.request,
        signal,
      ),
    finalize: async (current, accepted, signal) => {
      const result = await finalizeInitialEvidence(
        { ...current, result: accepted.result, speciesID: accepted.speciesID },
        initialEvidenceFinalizationDependencies(client),
        signal,
      );
      return result.responseEnvelope;
    },
  };
}
