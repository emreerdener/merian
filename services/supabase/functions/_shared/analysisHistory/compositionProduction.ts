import type { SupabaseClient } from "@supabase/supabase-js";
import { prepareAIExecution } from "../ai/production.ts";
import { exactObject, historyUUID, invalidHistory } from "./contract.ts";
import { PrivateHistoryEvidenceStorage } from "./evidenceStorage.ts";
import { analysisAuthority, historyWorkerRPC } from "./production.ts";
import {
  executeCompositionAnalysis,
  parseCompositionAnalysisWork,
} from "./compositionExecution.ts";
import { materializeCompositionAnalysis } from "./compositionMaterialization.ts";

/** Explicit V5 worker behind the versioned analysis gateway. Uses only the
 * composition claim/advance lane; legacy RPCs are never a fallback. */
export async function runOwnedCompositionAnalysis(
  client: SupabaseClient,
  owner: string,
  observation: string,
  analysis: string,
  value: unknown,
  signal: AbortSignal = AbortSignal.timeout(110_000),
) {
  historyUUID(owner);
  historyUUID(observation);
  historyUUID(analysis);
  const work = parseCompositionAnalysisWork(value, observation, analysis);
  const advance = (operation: string, payload: Record<string, unknown>) =>
    historyWorkerRPC(
      client,
      "advance_owned_observation_composition_analysis",
      {
        p_owner: owner,
        p_observation: observation,
        p_analysis: analysis,
        p_work: work.work_token ?? null,
        p_operation: operation,
        p_payload: payload,
      },
      operation === "materialize" || operation === "dispatch"
        ? signal
        : undefined,
    );
  return await executeCompositionAnalysis(work, {
    advance,
    prepare: async (dispatchWork) => {
      const authority = analysisAuthority(owner, dispatchWork);
      const receipt = await advance("materialize", {});
      const storage = new PrivateHistoryEvidenceStorage();
      const request = await materializeCompositionAnalysis(
        dispatchWork.input,
        owner,
        new TextEncoder().encode(JSON.stringify(receipt)),
        {
          read: (item, { signal }) => storage.readVerified(item, signal),
        },
        AbortSignal.any([signal, AbortSignal.timeout(20_000)]),
      );
      return prepareAIExecution(request, authority);
    },
    resolveSpecies: async () => {
      const value = await advance("resolve_species", {});
      if (value === null) return null;
      const row = exactObject(value, ["id", "scientific_name"]);
      if (
        typeof row.scientific_name !== "string" ||
        !row.scientific_name.trim() || row.scientific_name.length > 255
      ) return invalidHistory();
      return { id: historyUUID(row.id), scientific_name: row.scientific_name };
    },
  }, signal);
}
