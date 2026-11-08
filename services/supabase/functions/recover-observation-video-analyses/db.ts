import type { SupabaseClient } from "@supabase/supabase-js";
import { historyWorkerRPC } from "../_shared/analysisHistory/production.ts";
import { runOwnedVideoAnalysis } from "../_shared/analysisHistory/videoProduction.ts";
import { recoverObservationAnalyses } from "../recover-observation-analyses/handler.ts";
export async function recoverVideoAnalyses(client: SupabaseClient) {
  return await recoverObservationAnalyses({
    now: Date.now,
    list: () =>
      historyWorkerRPC(client, "list_observation_video_analysis_recovery", {}),
    recover: async (owner, observation, analysis) => {
      const work = await historyWorkerRPC(
        client,
        "claim_observation_video_analysis_recovery",
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
      const state = await runOwnedVideoAnalysis(
        client,
        owner,
        observation,
        analysis,
        work,
      );
      return state === "complete" || state === "failed_terminal";
    },
  }, 32);
}
