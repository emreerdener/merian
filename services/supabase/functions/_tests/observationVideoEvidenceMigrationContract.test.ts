import { assert } from "@std/assert";
Deno.test("video allocation keeps execution and erasure boundaries closed", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261010054046_prepare_video_evidence_allocation.sql",
      import.meta.url,
    ),
  );
  for (
    const required of [
      "video_evidence_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "ENABLE ROW LEVEL SECURITY",
      "observation_video_source_preexecution_clear",
      "observation_video_evidence_execution_clear",
      "expire_unbound_observation_evidence(uuid)",
      "expire_observation_evidence(uuid)",
      "merian-history-object:",
      "p_media UUID,p_object UUID",
      "item->'ready_at'<>'null'::JSONB",
      "internal.video_evidence_receipt(binding)",
      "private_evidence_erasure_enabled",
      "date_trunc('milliseconds',clock_timestamp())",
      "ON DELETE CASCADE",
    ]
  ) assert(sql.includes(required), required);
  assert(!/GRANT EXECUTE[^;]+TO (?:anon|authenticated)/.test(sql));
  assert(
    !/CREATE (?:OR REPLACE )?FUNCTION (?:public|internal)\.(?:dispatch|execute|refund|admit)_/
      .test(sql),
  );
});

Deno.test("video ready-evidence prerequisite stays private without execution authority", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261010135143_prepare_video_execution_evidence_guard.sql",
      import.meta.url,
    ),
  );
  assert(
    !/\bGRANT\b|CREATE (?:OR REPLACE )?FUNCTION public\.|ALTER TABLE/.test(sql),
  );
  for (
    const boundary of [
      "transaction_isolation",
      "lock_owned_observation_video_source_binding",
      "observation_video_source_cohort_items",
      "video_evidence_receipt",
      "ORDER BY media_id FOR UPDATE",
      "allocation.expires_at<=clock_timestamp()",
      "FROM PUBLIC,anon,authenticated,service_role",
    ]
  ) assert(sql.includes(boundary), boundary);
  assert(!sql.includes("INSERT INTO") && !sql.includes("UPDATE internal."));
});

Deno.test("video initial admission is private and exact funding does not wire execution", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261010142136_prepare_video_initial_admission.sql",
      import.meta.url,
    ),
  );
  assert(!/\bGRANT\b|CREATE (?:OR REPLACE )?FUNCTION public\./.test(sql));
  for (
    const boundary of [
      "video_analysis_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "assert_ready_video_analysis_evidence",
      "observation_video_evidence_execution_clear",
      "assert_observation_source_input_chain",
      "multimodal_video_frames_v1",
      "multimodal_video_audio_v1",
      "FROM PUBLIC,anon,authenticated,service_role",
    ]
  ) assert(sql.includes(boundary), boundary);
  assert(
    !sql.includes("pg_get_functiondef('public.begin_owned") &&
      !sql.includes("pg_get_functiondef('public.advance_owned"),
  );
});
