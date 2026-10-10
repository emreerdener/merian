import { assert, assertEquals } from "@std/assert";
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

Deno.test("video claim and dispatch remain private without public execution wiring", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261010144617_prepare_private_video_dispatch.sql",
      import.meta.url,
    ),
  );
  assert(
    !/\bGRANT\b|CREATE (?:OR REPLACE )?FUNCTION public\./
      .test(sql),
  );
  assertEquals(sql.match(/pg_get_functiondef/g)?.length, 1);
  assert(
    sql.includes(
      "pg_get_functiondef('internal.admit_video_observation_analysis(uuid,jsonb,text)'",
    ),
  );
  for (
    const boundary of [
      "video_dispatch_enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "assert_ready_video_analysis_evidence",
      "assert_observation_source_input_chain",
      "observation_analysis_dispatch_witnesses",
      "pg_catalog.pg_current_xact_id()",
      "may_dispatch',FALSE",
      "work_token IS DISTINCT FROM p_work_token",
      "FROM PUBLIC,anon,authenticated,service_role",
    ]
  ) assert(sql.includes(boundary), boundary);
});

Deno.test("video received outcome is private and cannot grant settlement or provider retry", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261010150954_prepare_private_video_outcome_recovery.sql",
      import.meta.url,
    ),
  );
  assert(!/\bGRANT\b|CREATE (?:OR REPLACE )?FUNCTION public\./.test(sql));
  for (
    const required of [
      "lock_video_observation_analysis",
      "assert_video_analysis_dispatch_identity",
      "record_video_observation_outcome",
      "read_video_observation_outcome",
      "saved.provider_outcome IS DISTINCT FROM p_value",
      "saved.state<>'dispatched'",
      "FOR KEY SHARE",
      "octet_length(p_value::TEXT)>1048576",
      "public.list_observation_analysis_recovery()",
      "AND input_snapshot->''schema_version''<>''4''::JSONB",
    ]
  ) assert(sql.includes(required));
  assert(
    !/PERFORM internal\.(?:complete_identification_usage|settle_complimentary_analysis|fail_observation_analysis)/
      .test(sql),
  );
  assert(!/SET work_token|may_dispatch.*TRUE|DELETE FROM/.test(sql));
});
