import type { SupabaseClient } from "@supabase/supabase-js";
import { historyWorkerRPC } from "../_shared/analysisHistory/production.ts";
import { runOwnedVideoAnalysis } from "../_shared/analysisHistory/videoProduction.ts";
import { runOwnedCompositionAnalysis } from "../_shared/analysisHistory/compositionProduction.ts";
import {
  exactObject,
  historyUUID,
  invalidHistory,
} from "../_shared/analysisHistory/contract.ts";
import { recoverObservationAnalyses } from "../recover-observation-analyses/handler.ts";

/** One shared scheduler budget, with separate typed claim/execution lanes. A
 * disabled family returns an empty discovery list; transport errors fail closed. */
export async function recoverVideoAnalyses(
  client: SupabaseClient,
  execution = {
    video: runOwnedVideoAnalysis,
    composition: runOwnedCompositionAnalysis,
  },
) {
  const families = new Map<string, "video" | "composition">();
  const key = (owner: string, observation: string, analysis: string) =>
    `${owner}/${observation}/${analysis}`;
  return await recoverObservationAnalyses({
    now: Date.now,
    list: async () => {
      const lists: {
        owner_id: string;
        observation_id: string;
        analysis_id: string;
      }[][] = [];
      for (const family of ["video", "composition"] as const) {
        const raw = await historyWorkerRPC(
          client,
          `list_observation_${family}_analysis_recovery`,
          {},
        );
        if (!Array.isArray(raw) || raw.length > 32) return invalidHistory();
        lists.push(raw.map((value) => {
          const row = exactObject(value, [
            "owner_id",
            "observation_id",
            "analysis_id",
          ]);
          const item = {
            owner_id: historyUUID(row.owner_id),
            observation_id: historyUUID(row.observation_id),
            analysis_id: historyUUID(row.analysis_id),
          };
          const identity = key(
            item.owner_id,
            item.observation_id,
            item.analysis_id,
          );
          if (families.has(identity)) return invalidHistory();
          families.set(identity, family);
          return item;
        }));
      }
      // Interleave families so a full video batch cannot hide mixed completions.
      return Array.from({ length: 32 }, (_, i) => [lists[0][i], lists[1][i]])
        .flat().filter(Boolean).slice(0, 32);
    },
    recover: async (owner, observation, analysis) => {
      const family = families.get(key(owner, observation, analysis));
      if (!family) return invalidHistory();
      const work = await historyWorkerRPC(
        client,
        `claim_observation_${family}_analysis_recovery`,
        { p_owner: owner, p_observation: observation, p_analysis: analysis },
      );
      if (
        !work || typeof work !== "object" || !("claimed" in work) ||
        work.claimed !== true
      ) return false;
      if (
        !("state" in work) ||
        (work.state !== "dispatched" && work.state !== "draft")
      ) throw new Error("analysis_history_unavailable");
      const run = execution[family];
      const state = await run(client, owner, observation, analysis, work);
      return state === "complete" || state === "failed_terminal";
    },
  }, 32);
}
