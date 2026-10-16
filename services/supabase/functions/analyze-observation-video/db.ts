import type { SupabaseClient } from "@supabase/supabase-js";
import { historyWorkerRPC } from "../_shared/analysisHistory/production.ts";
import { runOwnedVideoAnalysis } from "../_shared/analysisHistory/videoProduction.ts";
import { parsePreparedVideoAdmission } from "../_shared/analysisHistory/videoAdmission.ts";
export async function runVideoRequest(
  client: SupabaseClient,
  owner: string,
  value: unknown,
  ipHash: string,
  signal?: AbortSignal,
) {
  const input = parsePreparedVideoAdmission(value);
  signal?.throwIfAborted();
  const work = await historyWorkerRPC(
    client,
    "begin_owned_observation_video_analysis",
    { p_owner: owner, p_input: input, p_ip_hash: ipHash },
    signal,
  );
  return await runOwnedVideoAnalysis(
    client,
    owner,
    input.observation_id,
    input.analysis_id,
    work,
    signal,
  );
}
